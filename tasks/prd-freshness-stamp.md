# PRD: Freshness Stamp & Staleness Detection

## Introduction / Overview

Generated context files (CLAUDE.md, AGENTS.md, .cursorrules, GEMINI.md, etc.) are static snapshots
of a Rails application's structure. Once written to disk they carry no indication of when they were
produced or whether the underlying application has changed. AI assistants that read these files
cannot distinguish a freshly-generated snapshot from one that is weeks out of date, which causes
them to reason from stale model counts, route lists, and schema details.

This feature embeds a generation timestamp and a short hash of the two most-volatile source files
(schema.rb and routes.rb) as a comment header in every generated context file. It then adds
staleness detection to the existing `rails ai:doctor` command and introduces a new `rails ai:check`
task that exits non-zero when any bridge file is stale — enabling CI pipelines to enforce freshness.

---

## Goals

- Every generated bridge file must contain a human-readable generation timestamp and a short
  fingerprint derived from `db/schema.rb` and `config/routes.rb`.
- Running `rails ai:doctor` must report a warning for each bridge file whose embedded fingerprint
  does not match the current fingerprint of those two files.
- A new `rails ai:check` task must exit with a non-zero status code when any bridge file is stale,
  making it usable as a CI gate.
- A `--check` flag on `rails ai:bridge` must report staleness without regenerating files and exit
  non-zero if stale.
- The fingerprint must be cheap to compute (reading only schema.rb and routes.rb content, not
  the entire watched-file set used by `Fingerprinter`).

---

## User Stories

1. **As a developer**, I want every generated bridge file to show when it was produced and a
   hash of schema.rb + routes.rb, so that I — and any AI reading the file — can immediately see
   whether the snapshot is likely stale.

2. **As a developer running `rails ai:doctor`**, I want to be warned when a bridge file's embedded
   hash no longer matches the current schema.rb and routes.rb, so that I know to regenerate
   before giving context to an AI assistant.

3. **As a CI engineer**, I want a `rails ai:check` task that exits non-zero when any bridge file
   is stale, so that pull requests that modify schema.rb or routes.rb without regenerating bridge
   files are caught automatically.

4. **As a developer reviewing bridge files before committing**, I want to run
   `rails ai:bridge --check` and see a staleness report without triggering a full regeneration, so
   that I can decide whether to regenerate or proceed.

5. **As an AI assistant reading a bridge file**, I want the header comment to make it clear that
   the snapshot may not reflect the latest schema, so that I weight live MCP tool results more
   heavily than potentially outdated static counts.

---

## Functional Requirements

### 1. Freshness Header — All Generated Files

1.1. Every context file written by `ContextFileSerializer` must begin with a comment block
     (using the appropriate comment syntax for the file type) that contains:

     - `Generated at`: an ISO 8601 UTC timestamp (e.g. `2026-04-03T14:22:00Z`)
     - `Source fingerprint`: the first 12 hex characters of the SHA256 of the concatenated
       content of `db/schema.rb` and `config/routes.rb` (in that order).

1.2. The comment block must appear before any Markdown or file content so that even a
     plain-text read of the first two lines reveals freshness information.

1.3. For Markdown files (CLAUDE.md, AGENTS.md, GEMINI.md, .cursorrules, .windsurfrules,
     .github/copilot-instructions.md) the comment syntax is HTML comment: `<!-- ... -->`.

1.4. For the JSON file (`.ai-context.json`) the header must be added as a top-level
     `"_meta"` object with keys `generated_at` and `source_fingerprint` rather than a
     comment (JSON does not support comments).

1.5. The fingerprint must be computed from file **content** (not mtime), so that regenerating
     with an unchanged schema and routes produces the same fingerprint.

1.6. If `db/schema.rb` or `config/routes.rb` is absent, the missing file contributes an empty
     string to the hash input. The header is still written.

### 2. Staleness Detection in `rails ai:doctor`

2.1. `Doctor` must gain a new check named `"Bridge file freshness"`.

2.2. The check must locate every bridge file that exists on disk by scanning the paths defined
     in `ContextFileSerializer::FORMAT_MAP` relative to the configured output directory.

2.3. For each found file, the check must parse the `Source fingerprint` value from its header
     comment (or `_meta.source_fingerprint` for JSON).

2.4. The check computes the current fingerprint of `db/schema.rb` + `config/routes.rb` once
     and compares it against each file's embedded fingerprint.

2.5. If all found files have matching fingerprints the check reports `:pass`.

2.6. If one or more files have a mismatched fingerprint the check reports `:warn` and lists
     the stale file names in the message.

2.7. If no bridge files are found on disk the check reports `:warn` with a message directing
     the developer to run `rails ai:bridge`.

2.8. The check must not raise; any IO error reading a file is treated as a stale file and
     reported as `:warn`.

### 3. New `rails ai:check` Task

3.1. A new Rake task `rails ai:check` must be added to `rails_ai_bridge.rake`.

3.2. The task depends on `:environment`.

3.3. The task runs the staleness check logic (same as Requirement 2) and prints the result
     to stdout using the same icon/format as `rails ai:doctor`.

3.4. If all bridge files are fresh (fingerprints match) the task prints a success message and
     exits 0.

3.5. If any bridge file is stale or missing the task prints a descriptive message listing the
     affected files and exits with a non-zero status (`exit 1`).

3.6. The task must be documented so it can be used in CI YAML with
     `bundle exec rails ai:check`.

### 4. `--check` Flag on `rails ai:bridge`

4.1. `rails ai:bridge` must accept an environment variable `CHECK=1` (consistent with the
     existing `CONTEXT_MODE` and `FORMAT` env-var pattern used by the rake file) that enables
     check-only mode.

4.2. When `CHECK=1` is set the task must not write any files. It must compute the current
     fingerprint, compare it against each existing bridge file's embedded fingerprint, report
     the result, and exit 0 (all fresh) or 1 (any stale).

4.3. The output format in check mode mirrors `rails ai:check` output.

---

## Non-Goals (Out of Scope)

- Automatically regenerating bridge files when staleness is detected (that is the job of
  `rails ai:bridge`, optionally triggered by `rails ai:watch`).
- Tracking changes beyond `db/schema.rb` and `config/routes.rb` for the embedded fingerprint
  (the full `Fingerprinter` snapshot is intentionally broader and used for cache-invalidation
  elsewhere; the freshness stamp uses a deliberately narrow two-file hash for clarity).
- Displaying the freshness header to end users inside the AI assistant UI (that is outside the
  gem's control).
- Per-format freshness headers that differ structurally from the two formats specified
  (Markdown HTML comment and JSON `_meta`).
- Adding staleness detection to the MCP live tools (they always reflect live state).

---

## Design Considerations

- The freshness header should be invisible to most Markdown renderers. HTML comment syntax
  (`<!-- ... -->`) satisfies this — Markdown renderers do not render HTML comments.
- The 12-character truncated hash is short enough for a comment but long enough to detect any
  meaningful file change. It is not a security mechanism; collision resistance at this length
  is sufficient for drift detection.
- The `Doctor` check name `"Bridge file freshness"` should be added to `CHECKS` near
  `check_context_files` so the report groups related file checks together.
- `rails ai:check` should be documented in the gem's README under "CI Integration" alongside
  the existing `rails ai:bridge` command reference.

---

## Technical Considerations

- **Existing `Fingerprinter` class** (`lib/rails_ai_bridge/fingerprinter.rb`) uses mtime-based
  hashing for the broad snapshot. The new freshness fingerprint uses **content-based** SHA256
  on exactly two files. Introduce a dedicated class or module method, e.g.
  `Fingerprinter.source_fingerprint(app)`, that reads and digests only `db/schema.rb` and
  `config/routes.rb` content, returning the first 12 hex characters.
- **Header injection** must happen inside `ContextFileSerializer#call` before the content
  equality check, so a regeneration after a schema change always rewrites the file even if the
  rest of the content is identical.
- **Header parsing** for the staleness check requires a lightweight regex extractor. Consider
  a `FreshnessHeader` value object or module with two methods: `embed(content, timestamp, fingerprint)`
  and `extract_fingerprint(content)`.
- **`rails ai:check` exit code** must use `exit 1` inside the Rake task (not `abort`) to
  produce a clean non-zero exit without a Ruby backtrace.
- **No new gem dependencies** — `Digest::SHA256` is available in Ruby stdlib.

---

## Implementation Surface

| Area | Files likely touched |
|---|---|
| Core utility | `lib/rails_ai_bridge/fingerprinter.rb` — add `source_fingerprint` method |
| New utility | `lib/rails_ai_bridge/freshness_header.rb` — embed/extract header logic |
| Serializer orchestration | `lib/rails_ai_bridge/serializers/context_file_serializer.rb` — inject header before write |
| JSON serializer | `lib/rails_ai_bridge/serializers/json_serializer.rb` — add `_meta` block |
| Doctor checks | `lib/rails_ai_bridge/doctor.rb` — add `check_bridge_freshness` check |
| Rake tasks | `lib/rails_ai_bridge/tasks/rails_ai_bridge.rake` — add `ai:check`, `CHECK=1` branch |
| Specs | `spec/rails_ai_bridge/freshness_header_spec.rb`, `spec/rails_ai_bridge/fingerprinter_spec.rb`, `spec/rails_ai_bridge/doctor_spec.rb`, `spec/rails_ai_bridge/serializers/context_file_serializer_spec.rb` |

---

## Success Metrics

- Every bridge file written after this feature ships begins with a freshness header comment on
  its first two lines.
- `rails ai:doctor` reports `:warn` for any bridge file whose embedded fingerprint differs from
  the live fingerprint — verifiable by manually editing schema.rb after generation.
- `rails ai:check` exits 0 on a freshly-generated set of bridge files and exits 1 after any
  change to schema.rb or routes.rb without regeneration — verifiable in a CI environment.
- Spec coverage for `FreshnessHeader` embed/extract round-trip is 100% (both happy path and
  missing-file edge cases).
- No existing specs are broken by the new header (equality-check skip logic in
  `ContextFileSerializer` accounts for the updated header).

---

## Open Questions

1. Should the freshness header also include the `rails-ai-bridge` gem version to help diagnose
   incompatibility between old files and a newly upgraded gem? (Currently out of scope but
   trivial to add alongside the timestamp.)

2. Should `rails ai:check` check split rule files (`.claude/rules/`, `.cursor/rules/`, etc.) in
   addition to the top-level bridge files, or only the files listed in `FORMAT_MAP`? The split
   files do not currently embed any metadata, so this would require a separate tracking mechanism.

3. Should the Doctor `check_bridge_freshness` check be `:fail` (rather than `:warn`) when files
   are stale? Currently `:fail` is reserved for missing components that prevent the MCP server
   from functioning; stale context files are an accuracy issue, not a functionality issue.

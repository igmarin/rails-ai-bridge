# PRD: Incremental Updates & CI/CD Integration

## 1. Introduction / Overview

Currently, `rails ai:bridge` regenerates all context files from scratch on every invocation, regardless of whether the underlying application data has changed. For large Rails apps with many models, routes, and views, this is unnecessarily slow. It also makes CI integration costly because a full introspection pass runs after every migration merge, even if only one table changed.

This feature makes context regeneration incremental by wiring up the existing `Fingerprinter` to track per-introspector staleness, adds an official GitHub Actions workflow template for automated CI updates, introduces a `--check` flag for pre-commit gate usage, and improves CLI output to surface timing and file status clearly.

---

## 2. Goals

- Reduce average `rails ai:bridge` runtime on large Rails apps by skipping introspectors whose inputs have not changed since the last run.
- Enable CI pipelines to run `rails ai:bridge` cheaply after every migration merge without full regeneration overhead.
- Provide a zero-config GitHub Actions workflow template that developers can opt into during `rails generate rails_ai_bridge:install`.
- Give developers a low-friction way to ensure context files are never committed in a stale state via a `--check` mode.
- Make CLI output actionable: show per-file status (written / skipped) and total elapsed time on every run.

---

## 3. User Stories

**3.1 Incremental regeneration**
As a developer on a large Rails app, I want `rails ai:bridge` to skip introspectors whose source files have not changed so that the command completes in seconds instead of tens of seconds on repeated runs.

**3.2 CI auto-update**
As a team lead, I want a GitHub Actions workflow that runs `rails ai:bridge` after migrations are merged and commits the updated context files back to the branch so that context files are always in sync without manual developer discipline.

**3.3 Pre-commit gate**
As a developer who cares about context freshness, I want to optionally install a git pre-commit hook that runs `rails ai:bridge --check` and fails the commit if any context file is stale, so that stale context never lands in the repo.

**3.4 Clear CLI output**
As a developer running `rails ai:bridge`, I want to see which files were rewritten, which were skipped as unchanged, and how long the run took so that I can quickly confirm the command did what I expected.

---

## 4. Functional Requirements

### 4.1 Incremental Regeneration

1. The gem must persist a fingerprint cache file (e.g., `tmp/rails_ai_bridge_fingerprints.json`) that maps each introspector name to its last-computed input fingerprint and the SHA256 of the last-written output.
2. On each `rails ai:bridge` run, the gem must compute a fingerprint for each introspector's input sources (using the existing `Fingerprinter` logic, scoped per-introspector) and compare it against the cache.
3. An introspector must be re-run only when its input fingerprint has changed since the last run.
4. A context file must be rewritten only when its rendered content differs from the last-written version (content-hash comparison, not just mtime).
5. The fingerprint cache must be updated atomically after a successful run to avoid partial-write corruption.
6. The fingerprint cache file must be added to `.gitignore` by the install generator (it is a local build artifact, not a project file).
7. Passing `--force` (or `FORCE=1` env var) to `rails ai:bridge` must bypass all fingerprint checks and regenerate everything, useful as an escape hatch.

### 4.2 GitHub Actions Workflow Template

8. The gem must ship a template file at `lib/generators/rails_ai_bridge/install/templates/rails-ai-bridge.yml` that defines a GitHub Actions workflow.
9. The workflow must trigger on `push` to the default branch when any file under `db/migrate/`, `db/schema.rb`, `app/models/`, `config/routes.rb`, or `Gemfile.lock` changes.
10. The workflow must check out the repo, set up Ruby, run `bundle exec rails ai:bridge`, and commit any changed context files back to the triggering branch using a bot identity (e.g., `github-actions[bot]`).
11. The workflow must use `git diff --exit-code` before committing to skip the commit step when nothing changed, preventing empty commits.
12. The install generator (`rails generate rails_ai_bridge:install`) must ask the developer whether to create `.github/workflows/rails-ai-bridge.yml` and only create it on affirmative response.
13. If the developer declines during install, the workflow template must remain accessible in the gem so they can add it manually later (document the path in install output).

### 4.3 Pre-commit Hook

14. `rails ai:bridge --check` must run the full introspection and context rendering pipeline but must not write any files.
15. `rails ai:bridge --check` must exit with status code `0` when all context files are up to date (rendered content matches on-disk files).
16. `rails ai:bridge --check` must exit with status code `1` and print the list of stale files when any context file is out of date.
17. The install generator must ask the developer whether to install a git pre-commit hook at `.git/hooks/pre-commit` that calls `bundle exec rails ai:bridge --check`.
18. The pre-commit hook option must default to "no" (opt-in). The generator must not install the hook silently.
19. If a pre-commit hook already exists at `.git/hooks/pre-commit`, the generator must not overwrite it; instead it must print instructions for the developer to append the check manually.
20. The `--check` flag must be documented in `rails ai:bridge --help` output.

### 4.4 CLI Output Improvements

21. `rails ai:bridge` must print the total elapsed wall-clock time at the end of every run (e.g., `Done in 2.4s`).
22. The existing per-file status output (`written` / `skipped`) must be printed for every run, not just on change.
23. `rails ai:bridge` must print a summary line counting how many files were written vs. skipped (e.g., `3 written, 4 skipped`).
24. When running in incremental mode, the output must indicate how many introspectors were skipped due to unchanged inputs (e.g., `12 of 15 introspectors skipped (inputs unchanged)`).
25. Output formatting must remain machine-parseable enough for CI log scraping: each file status line must start with a consistent prefix (`WRITTEN:` or `SKIPPED:`), and the summary line must be identifiable by a consistent prefix (`SUMMARY:`). Existing emoji output is fine for human-readable output as long as the prefixes are also present.

---

## 5. Non-Goals (Out of Scope)

- Per-format incremental caching (e.g., regenerating only the Claude format while skipping Cursor). All output formats are regenerated together when inputs are stale; this can be revisited in a future iteration.
- Remote or shared fingerprint caches across team members or CI agents. The cache is local and per-run-environment.
- Automatic installation of GitHub Actions or pre-commit hooks without developer consent. All CI/hook setup requires explicit opt-in.
- Parallelising introspector execution (separate performance concern).
- Support for non-GitHub CI systems (GitLab CI, CircleCI, Buildkite). The workflow template targets GitHub Actions only. Developers using other systems can adapt the rake invocation manually.
- Watching for changes in real time (that is already handled by `rails ai:watch` / `Watcher`).
- Modifying the `rails ai:watch` code path to use the incremental cache (can be a follow-up).

---

## 6. Design Considerations

- The fingerprint cache file (`tmp/rails_ai_bridge_fingerprints.json`) must use a stable JSON format so it can survive gem upgrades. Include a `schema_version` key so future breaking changes can be detected and the cache invalidated automatically.
- The `--check` output must be CI-friendly: no color codes on non-TTY output, one stale file per line.
- The GitHub Actions workflow template must use `actions/checkout` with `persist-credentials: true` and a `GITHUB_TOKEN`-based push so no external secrets are required for basic usage.
- Pre-commit hook installation must be idempotent: running the install generator twice must not produce a duplicate hook entry.

---

## 7. Technical Considerations

- The existing `Fingerprinter.snapshot(app)` produces a single global hash across all watched files. Incremental support requires scoping fingerprints per-introspector. Each introspector's input scope (which files or directories it reads) must be expressible as a list that `Fingerprinter` can hash independently, without breaking the existing global snapshot interface.
- The fingerprint cache must survive between `rails ai:bridge` invocations in CI. CI runners typically start from a clean checkout, so the cache will be cold on the first run after each checkout. Developers can optionally cache `tmp/rails_ai_bridge_fingerprints.json` in GitHub Actions using `actions/cache` — document this in the workflow template comments.
- The `--check` flag must not require a database connection beyond what introspectors already need; it runs the same introspection pipeline as a normal run.
- The install generator currently runs `generate_context` at the end of setup. The `--check` pathway must be clearly separate from the install flow.
- The commit step in the GitHub Actions workflow must use `git config user.email "github-actions[bot]@users.noreply.github.com"` and `git config user.name "github-actions[bot]"` to attribute commits correctly in the repository history.

---

## 8. Implementation Surface

- `lib/rails_ai_bridge/fingerprinter.rb` — extend to support per-introspector scoped snapshots
- `lib/rails_ai_bridge/introspector.rb` — wire per-introspector fingerprint checks; skip re-run when input is unchanged
- `lib/rails_ai_bridge/tasks/rails_ai_bridge.rake` — add `--check` flag handling, timing output, summary line, `--force` bypass
- `lib/generators/rails_ai_bridge/install/install_generator.rb` — add opt-in prompts for GitHub Actions workflow and pre-commit hook
- `lib/generators/rails_ai_bridge/install/templates/rails-ai-bridge.yml` — new GitHub Actions workflow template
- `lib/generators/rails_ai_bridge/install/templates/pre-commit` — new pre-commit hook shell script template
- `tmp/rails_ai_bridge_fingerprints.json` — runtime artifact (not shipped, added to `.gitignore`)
- `docs/` or `README.md` — pre-commit hook guidance and CI integration documentation

---

## 9. Success Metrics

- On a Rails app with 30+ models and no source changes since the last run, `rails ai:bridge` completes in under 3 seconds (vs. current baseline of 10–30 seconds on large apps).
- The GitHub Actions workflow template can be copied into a real repo and produces a passing CI run without modification, including the commit-back step.
- `rails ai:bridge --check` exits `0` on a freshly generated context and exits `1` after a model file is touched without re-running `rails ai:bridge`.
- CLI output always includes a `SUMMARY:` line and per-file `WRITTEN:` / `SKIPPED:` lines that can be parsed by a simple `grep` in a CI script.
- Zero incidents of the install generator silently overwriting an existing pre-commit hook.

---

## 10. Open Questions

1. **Per-introspector input scoping**: How granular should the input scope be? For example, does the `models` introspector watch only `app/models/**/*.rb`, or also `db/schema.rb`? A formal mapping of introspector → watched paths needs to be defined before implementation.
2. **Cache invalidation on gem upgrade**: Should a gem version bump always bust the fingerprint cache, or only when the introspector output format changes? Using a `schema_version` key is proposed but the exact invalidation policy needs agreement.
3. **GitHub Actions token permissions**: Some repositories require explicit `contents: write` permission on the workflow job. Should the template include this by default (slightly broader permissions) or leave it commented out with a note?
4. **`--check` in watch mode**: Should `rails ai:watch` also support a `--check` style dry-run, or is that out of scope for this iteration?
5. **Windows compatibility**: The pre-commit hook is a shell script. Is `.git/hooks/pre-commit` shell script support sufficient, or should a Ruby-based hook runner be provided for cross-platform compatibility?

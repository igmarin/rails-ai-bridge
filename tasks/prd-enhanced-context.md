# PRD: Enhanced Context — Testing Patterns, Job Conventions & API Documentation

## 1. Introduction / Overview

Three of the gem's introspectors produce shallow output that leaves AI assistants without the
context they need to generate compatible code: `TestIntrospector` identifies a testing framework
but omits factory strategy, shared-example patterns, and CI parallelisation; `JobIntrospector`
lists job class names but says nothing about retry strategies, idempotency, or Sidekiq
configuration; `ApiIntrospector` detects serializer files but cannot distinguish JSON:API from
custom formats, nor report pagination or API-authentication approaches.

The result is that AI assistants (Windsurf, Gemini, Copilot, Claude) generate test syntax that
conflicts with the project's factory setup, produce jobs that miss idempotency requirements, and
scaffold API endpoints in the wrong format. This feature deepens the output of all three
introspectors so that the context files and MCP tool responses contain the information AI
assistants actually need.

---

## 2. Goals

- `TestIntrospector#call` must surface factory strategy (FactoryBot vs fixtures), shared-example
  file count, spec-helper configuration flags, dominant spec types by directory count, and CI
  parallelisation/coverage tooling.
- `JobIntrospector#call` must surface per-job retry configuration, queue names with priorities,
  idempotency indicators, Sidekiq-specific configuration (concurrency, queue list from
  `sidekiq.yml`), and recurring-job setup (sidekiq-cron, GoodJob, Solid Queue cron).
- `ApiIntrospector#call` must surface serializer format family (JSON:API, Grape entity, custom),
  API versioning strategy (module namespace, Accept header, URL path), pagination library
  (Kaminari, Pagy, cursor-based), and API authentication method (JWT, API key, session).
- All new output keys must be populated from static-file analysis (directory structure, Gemfile,
  config files) so that the introspectors continue to work without a running database.
- Every new key must be present in the hash with a defined sentinel value (`nil`, `[]`, or `{}`)
  when the feature it describes is absent — callers must never receive a `KeyError`.
- No introspector may raise an exception; all new code paths must be wrapped in the existing
  rescue convention (`{ error: e.message }`).
- Existing spec coverage for these three introspectors must be updated so the new keys are
  exercised; overall spec count must not decrease.

---

## 3. User Stories

**As an AI assistant** reading the generated context file, I want to know whether the project uses
FactoryBot factories or fixtures, so that I generate test scaffolding that matches the project's
existing test strategy.

**As an AI assistant** reading the generated context file, I want to see each job's retry limit
and queue name, so that I produce job classes that respect the project's reliability conventions.

**As an AI assistant** reading the generated context file, I want to know whether the API uses
JSON:API format and Pagy for pagination, so that I produce serializer and controller code that is
compatible with existing endpoints.

**As a gem user** whose team uses Sidekiq with a `sidekiq.yml` file, I want the MCP context to
include concurrency and queue configuration, so that AI assistants do not hardcode queue names or
suggest wrong concurrency values.

**As a gem user** running RSpec with parallel_tests and SimpleCov, I want the context to reflect
that setup, so that AI assistants suggest CI configuration changes that are consistent with what
is already in place.

---

## 4. Functional Requirements

### 4.1 TestIntrospector

1. The `call` result must include a `:factory_strategy` key with value `"factory_bot"`,
   `"fixtures"`, `"both"`, or `nil` (none detected).
2. `:factory_strategy` must be `"factory_bot"` when `spec/factories/` or `test/factories/`
   contains at least one `.rb` file.
3. `:factory_strategy` must be `"fixtures"` when `spec/fixtures/` or `test/fixtures/` contains
   at least one `.yml` file and no factory directory exists.
4. `:factory_strategy` must be `"both"` when both factory files and fixture files are present.
5. The `call` result must include a `:shared_examples` key with the count of files matching
   `spec/support/shared_examples/**/*.rb` or `spec/shared_examples/**/*.rb` (integer, `0` when
   none).
6. The `call` result must include a `:spec_types` key with a hash of spec directory counts, e.g.
   `{ models: 4, requests: 12, system: 2 }`. Only directories that contain at least one `.rb`
   file must be included. Recognised directory names under `spec/`: `models`, `requests`,
   `controllers`, `system`, `mailers`, `jobs`, `services`, `helpers`, `channels`, `views`.
7. The `call` result must include a `:parallel_tests` boolean: `true` when `parallel_tests` or
   `parallel-tests` appears in `Gemfile.lock`.
8. The `:coverage` key must already exist (it does); its detection logic must be extended to also
   recognise `simplecov-rails` as `"simplecov"`.
9. All existing keys must remain unchanged and backward-compatible.

### 4.2 JobIntrospector

10. The `call` result must include a `:retry_strategies` key — an array of hashes, one per
    detected job class, each with keys `:name` (String), `:retry` (Integer or `nil`), and
    `:queue` (String).
11. `:retry` must be read from the job class's `rescue_from` blocks or `retry_on` declarations
    via source-file scanning when reflection is not sufficient. When undetermined it must be
    `nil`.
12. The `call` result must include a `:sidekiq_config` key — a hash with `:concurrency`
    (Integer or `nil`) and `:queues` (Array of strings), populated by parsing `config/sidekiq.yml`
    or `sidekiq.yml` at the Rails root. The key must be `nil` when no Sidekiq config file is
    found.
13. The `call` result must include a `:recurring_jobs` key — a string naming the recurring-job
    library (`"sidekiq_cron"`, `"good_job"`, `"solid_queue"`, `"whenever"`) or `nil`. Detection
    is via `Gemfile.lock` or the presence of a `config/recurring.yml` (Solid Queue / GoodJob).
14. The `call` result must include an `:idempotency_indicators` array — file paths (relative to
    Rails root) of job source files that contain the string `idempotent`, `deduplicate`, or
    `unique` (case-insensitive). An empty array is valid when none are found.
15. The existing `:jobs` array must retain its current shape (`name`, `queue`, `priority`); no
    existing keys may be removed.

### 4.3 ApiIntrospector

16. The `call` result must include a `:serializer_format` key with value `"jsonapi"`, `"grape"`,
    `"jbuilder"`, `"custom"`, or `nil`. Detection rules:
    - `"jsonapi"` — `Gemfile.lock` includes `jsonapi-serializer` or `active_model_serializers`
      with JSONAPI adapter, or any serializer file contains `JSONAPI`.
    - `"grape"` — `Gemfile.lock` includes `grape-entity` or `grape`.
    - `"jbuilder"` — `detect_serializers` already counts `.jbuilder` files; use that count > 0.
    - `"custom"` — serializer classes directory exists but none of the above match.
17. The `call` result must include a `:versioning_strategy` key with value `"url_path"`,
    `"accept_header"`, `"module_namespace"`, or `nil`. Detection rules:
    - `"url_path"` — route file contains `/v\d/` path segments (regex scan of
      `config/routes.rb`).
    - `"accept_header"` — any controller file contains `Accept` header negotiation (`request.headers["Accept"]`).
    - `"module_namespace"` — API versioned directories exist under `app/controllers/api/v*/` and
      controller files contain `module V` declarations.
    - Multiple strategies may coexist; when they do the value must be an array of matching
      strings instead of a single string.
18. The `:api_versioning` key must be retained as-is (array of version directory names) for
    backward compatibility.
19. The `call` result must include a `:pagination` key with value `"kaminari"`, `"pagy"`,
    `"will_paginate"`, `"cursor"`, or `nil`. Detection is via `Gemfile.lock`.
    - `"cursor"` — `Gemfile.lock` includes `pagy` with cursor extension, or `cursor_paginates_for`
      appears in any model file.
20. The `call` result must include an `:api_auth` key — an array of detected authentication
    methods from: `"jwt"` (`jwt` or `knock` in `Gemfile.lock`), `"api_key"` (any controller
    file checks `params[:api_key]` or `request.headers["X-Api-Key"]`), `"devise_token_auth"`
    (`devise-token-auth` in `Gemfile.lock`), `"session"` (controllers inherit from
    `ActionController::Base` without api_only). An empty array is valid.

---

## 5. Non-Goals (Out of Scope)

- This feature does not add new MCP tools or new serializer sections. It only enriches the output
  hash of three existing introspectors. Serializer templates that render these keys are a
  separate concern and are not changed here.
- This feature does not parse Ruby ASTs or use `RuboCop::ProcessedSource`. All detection is
  plain-text scanning (`File.read`, regex, `Dir.glob`).
- This feature does not add introspection of Minitest-specific patterns (e.g. test macros). Only
  file-system-level detection is in scope.
- This feature does not add new introspectors for Action Mailer retry logic or Active Cable
  authentication.
- Detecting custom pagination implemented without a gem (e.g. raw `OFFSET`/`LIMIT` queries) is
  out of scope.
- Modifying the `Doctor` readiness scorer or the `Watcher` file observer is out of scope.

---

## 6. Technical Considerations

- All detection must operate via file-system reads. No `Kernel#require` of user-app code outside
  what is already loaded by the Rails engine boot.
- `Gemfile.lock` is the authoritative source for gem presence checks. `Gemfile` must not be
  parsed as a fallback because it requires evaluation.
- YAML parsing of `sidekiq.yml` must rescue `Psych::Exception` and return `nil` on malformed
  files.
- The `:spec_types` hash in `TestIntrospector` must only include keys for directories that
  actually contain `.rb` files, to keep the output compact (≤150-line convention).
- `JobIntrospector` currently uses `ActiveJob::Base.descendants` for runtime reflection. The new
  `:retry_strategies` key may use the same runtime list supplemented by source-file scanning for
  `retry_on` call arguments.
- File scanning loops must rescue `Errno::EACCES` and `Errno::ENOENT` per-file and continue
  rather than abort.

---

## 7. Implementation Surface

- `lib/rails_ai_bridge/introspectors/test_introspector.rb` — add private methods for factory
  strategy, shared examples, spec types, parallel tests.
- `lib/rails_ai_bridge/introspectors/job_introspector.rb` — add private methods for retry
  strategies, Sidekiq config parsing, recurring jobs, idempotency indicators.
- `lib/rails_ai_bridge/introspectors/api_introspector.rb` — add private methods for serializer
  format, versioning strategy, pagination, API auth.
- `spec/lib/rails_ai_bridge/introspectors/test_introspector_spec.rb` — extend with new key coverage.
- `spec/lib/rails_ai_bridge/introspectors/job_introspector_spec.rb` — extend with new key coverage.
- `spec/lib/rails_ai_bridge/introspectors/api_introspector_spec.rb` — extend with new key coverage.
- `spec/internal/` (combustion dummy app) — may need additional fixture files
  (`sidekiq.yml`, factory stubs) for test isolation.

---

## 8. Success Metrics

- All three introspector spec files pass with no failures after the change.
- The total spec count does not decrease from its baseline (364 examples as of v2.1.0).
- Running `bundle exec rspec spec/lib/rails_ai_bridge/introspectors/` against a sample Rails app
  that uses FactoryBot, Sidekiq, and `jsonapi-serializer` produces a result hash containing
  `factory_strategy: "factory_bot"`, `sidekiq_config: { concurrency: Integer, queues: Array }`,
  and `serializer_format: "jsonapi"` respectively.
- `bundle exec rubocop` passes with no new offenses.
- No existing key in any of the three introspector result hashes changes its name or type.
- AI assistant feedback (Windsurf, Gemini) no longer reports "missing testing patterns",
  "limited background job information", or "no API documentation patterns" on the updated context
  files.

---

## 9. Open Questions

1. Should `:versioning_strategy` return a single string or always an array? The requirement
   above allows both forms depending on how many strategies are detected — this may complicate
   consumer code. Consider always returning an array for consistency.
2. Should the `:spec_types` counts include subdirectory files recursively, or only the direct
   children of each named directory?
3. The `retry_on` detection via source scanning may produce false positives for commented-out
   code. Is a comment-stripping pass necessary, or is the risk acceptable given the read-only,
   advisory nature of the output?
4. `"cursor"` pagination detection by scanning all model files for `cursor_paginates_for` could
   be slow on large apps. Should this scan be limited to a file count threshold or skipped when
   the project has more than N model files?
5. Should the Sidekiq config parser also look for `config/sidekiq/*.yml` (multi-file Sidekiq
   configs used in some setups)?

# Ruby Version Support Policy

This document describes which Ruby and Rails versions `rails-ai-bridge` officially
supports, how the test matrix is structured, and how new Ruby/Rails releases are
evaluated.

## Supported Matrix

| Ruby | Rails | CI status | Notes |
|------|-------|-----------|-------|
| 3.2  | 7.1, 7.2 | ✅ enabled | Minimum supported |
| 3.3  | 7.1, 7.2, 8.0, 8.1 | ✅ enabled | Primary dev target |
| 3.4  | 7.1–8.1 | ✅ enabled | Default in CI since 5.4 |
| 3.5  | 7.1–8.1 | ✅ enabled | Added in 5.4, optional |
| 4.0  | 8.1 | ⚠️ canary | Non-blocking; used to detect breaking changes |

**Rails versions covered:** 7.1, 7.2, 8.0, 8.1, 8.2

## Evaluation Policy for New Releases

When a new Ruby or Rails point release lands:

1. **Check for breaking changes** that affect application introspection:
   - Ruby language feature additions (pattern matching, `Regexp` changes, method removals).
   - Rails framework changes (config refactor, new middleware, autoloading changes).
   - Dependency updates (zeitwerk, mcp SDK, rubydex).

2. **Add a CI row** if the version is stable enough to run the full suite.

3. **Add a canary row** if the version is pre-release or expected to break — marked as
   `continue-on-error`.

4. **Update this document** and bump the gemspec `required_ruby_version` only when
   dropping a previously-supported version.

## Gemspec Boundary

```ruby
spec.required_ruby_version = '>= 3.2.0'
spec.required_rubygems_version = '>= 3.4'
spec.add_dependency 'railties', '>= 7.1', '< 10.0'
```

The `railties` upper bound (`< 10.0`) is intentionally loose: new Rails releases are
evaluated per-point but only pinned in CI, not in the gemspec until a major bump is
planned.

## Version Manager Awareness

The gem reads `config.time_zone` and `Time.zone` at runtime via the host Rails app.
The Ruby version used by the host app must be compatible with the gem's required
version; `rbenv`, `asdf`, or `mise`/`fnm` version managers should pin Ruby to `>= 3.2`,
`>= 3.3` recommended for new projects.

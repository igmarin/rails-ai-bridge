# Ruby Version Support Policy

`rails-ai-bridge` requires Ruby >= 3.2 and Rails >= 7.1, < 10.0.
The supported combinations are the blocking rows below. A version accepted by
Bundler is not necessarily covered by CI.

## Tested matrix

| Ruby | Rails | CI status |
|------|-------|-----------|
| 3.2 | 7.1, 7.2 | Blocking; minimum supported Ruby |
| 3.3 | 7.1, 7.2, 8.0, 8.1 | Blocking |
| 3.4 | 7.1, 7.2, 8.0, 8.1 | Blocking; local development target |
| 4.0 | 8.1 | Non-blocking compatibility canary |

Ruby 3.2 is tested only with Rails 7.1 and 7.2. Newer Rails rows run on
Ruby 3.3 or later.

Ruby 3.5.0-preview1 is a historical preview, not a supported stable series.
It is excluded from CI: its native `rubydex` dependency cannot load, and the
current stable successor is [Ruby 4.0](https://www.ruby-lang.org/en/news/2025/12/25/ruby-4-0-0-released/).
See the [Ruby release list](https://www.ruby-lang.org/en/downloads/releases/).
Ruby 4.0 stays a canary until the full supported Rails matrix and dependencies
are validated; success in its single Rails 8.1 job does not establish full support.

## Language and standard library baseline

Runtime code must work on Ruby 3.2. No Ruby 3.4-only language or standard
library feature is required. For example, `Data.define` is available on Ruby
3.2 and `Regexp#match?` predates it; neither requires raising the minimum.
Optional tooling must remain guarded or isolated when it needs a newer Ruby.
The blocking Ruby 3.2 jobs validate the minimum against Rails 7.1 and 7.2.

The root `.ruby-version` pins the local development interpreter. It does not
set the gem's minimum version or replace the CI matrix. Use `rbenv`, `asdf`,
or `mise` to install the pinned Ruby before running Bundler.

## Evaluating new releases

1. Check language, Rails reflection APIs, and dependency compatibility.
2. Run the full suite for each compatible Ruby/Rails combination. Use a
   non-blocking canary for versions still under evaluation.
3. Promote a version to blocking only after its intended matrix passes.
4. Update this page, README Requirements, and CHANGELOG together. A minimum
   Ruby increase drops support and must be documented as a breaking change.

## Gemspec boundary

```ruby
spec.required_ruby_version = '>= 3.2.0'
spec.required_rubygems_version = '>= 3.4'
spec.add_dependency 'railties', '>= 7.1', '< 10.0'
```

The Ruby minimum remains 3.2 because no newer feature is required. The Rails
upper bound permits dependency resolution for newer releases; only the tested
matrix above is claimed as supported. `zeitwerk ~> 2.6` likewise permits
compatible 2.x updates without requiring a newer Ruby baseline in this gem.

# Test coverage (SimpleCov)

Configuration lives in [`spec/simplecov_helper.rb`](../spec/simplecov_helper.rb): **minimum 80% line coverage** over `lib/**/*.rb` (with a few filters for templates and bundled gems).

## Regenerate the per-file report

```bash
bundle exec rspec
open coverage/index.html   # macOS
```

## Regenerate the “below 80%” file list

After a full `bundle exec rspec` run (with SimpleCov enabled locally):

```bash
ruby -rjson -e '
root = Dir.pwd
data = JSON.parse(File.read("coverage/.resultset.json"))
cov = data.values.first["coverage"]
cov.each do |path, info|
  next unless path.start_with?("#{root}/lib/")
  lines = info["lines"] || []
  rel = path.sub("#{root}/", "")
  relevant = lines.reject(&:nil?)
  next if relevant.empty?
  hit = relevant.count { |n| n > 0 }
  pct = hit * 100.0 / relevant.size
  printf "%5.1f%%  (%d/%d)  %s\n", pct, hit, relevant.size, rel if pct < 80.0
end
' | sort -n
```

## Snapshot: files under 80% (2026-03-21, ~81% global)

Use this as a **prioritized backlog**; re-run the script above after adding tests.

| Priority | File | Notes |
| -------- | ---- | ----- |
| High | `lib/rails_ai_bridge/watcher.rb` | 0% — add unit specs for file watching / regeneration hooks. |
| Low | `lib/rails_ai_bridge/version.rb` | 0% — single source of truth; optional one-line load spec or `add_filter` if you prefer not to count it. |
| Medium | `lib/generators/.../install_generator.rb` | Partial coverage — extend generator specs for remaining branches. |
| Medium | `lib/rails_ai_bridge/server.rb` | HTTP `start` / `rackup` branches — specs with doubles or integration-style smoke. |
| Medium | `lib/rails_ai_bridge/engine.rb` | Initializers / middleware registration — lightweight config or integration spec. |
| Medium | `lib/rails_ai_bridge/tasks/rails_ai_bridge.rake` | Uncovered rake paths — task specs or invocation examples. |
| Medium | `lib/rails_ai_bridge/doctor.rb` | Remaining checks / branches — add examples per check or error path. |
| Low–Med | `lib/rails_ai_bridge/tools/get_{config,gems,test_info,conventions}.rb` | Tool `.call` branches not hit — add examples mirroring other tool specs. |
| Low–Med | `lib/rails_ai_bridge/tools/search_code.rb` | Edge paths (ripgrep vs Ruby fallback, limits) — characterization specs. |
| Low–Med | Introspectors (`job_`, `multi_database_`, `database_stats_`, `schema_`) | Conditional branches for optional app layouts — fixture-driven specs. |
| Low–Med | `lib/rails_ai_bridge/serializers/markdown_serializer.rb` | Large serializer — section-oriented specs or shared examples. |

When global coverage hovers near 80%, prefer tests for **public runtime paths** (MCP server, middleware, tools) before chasing every introspector branch.

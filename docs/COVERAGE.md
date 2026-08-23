# Code quality checks

The repository uses focused checks for behavior, style, code smells, documentation, and mutation resistance. Run the narrowest check while working, then run the full set before opening a pull request.

## Coverage

RSpec runs with SimpleCov. Focused specs do not enforce the global floor because they load only part of the library. The full command does:

```bash
COVERAGE=1 bundle exec rspec
```

The v5 release floor is **90% line coverage and 90% branch coverage**. The first quality-gate change uses the current branch baseline as a temporary floor while the debt-burning work raises it.

## RuboCop

```bash
bundle exec rubocop --parallel
```

RuboCop is the style source of truth. Do not add a local exception before checking whether the code can be simplified to match the existing style.

## Reek

```bash
bundle exec rake quality:reek
bundle exec reek lib/rails_ai_bridge/path_resolver.rb
bundle exec reek lib/ --format json
```

`.reek.yml` contains the reviewed baseline for existing smells. New smells fail CI. When a smell is fixed, remove its baseline entry. Keep an exception only when the method's public interface or safety behavior makes the smell intentional, and document that reason next to the exception.

## YARD

```bash
bundle exec rake docs:yard
YARD_MINIMUM_PERCENT=100 bundle exec rake docs:yard
```

The default gate protects the current documented baseline. The release gate is 100% for public classes and methods added or changed by v5; missing documentation must be fixed rather than hidden by changing the threshold.

## Mutation testing

```bash
BUNDLE_GEMFILE=Gemfile-mutation bundle exec mutant run RailsAiBridge::Registry::Resolver
```

Mutation testing is focused on security-sensitive and high-value behavior. A v5 release candidate must meet the critical-subject score defined in the release plan.

## Other gates

```bash
bundle exec skunk lib/
bundle exec bundle-audit check
bundle exec archspec check
```

Skunk protects complexity, bundler-audit checks dependency advisories, and ArchSpec checks dependency direction and cycles. The CI workflow is authoritative for which gates are blocking.

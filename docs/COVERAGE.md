# Code Quality Analysis (Reek)

Configuration lives in [`spec/reek_helper.rb`](../spec/reek_helper.rb). Reek analyzes code for smells and quality issues.

## Running Reek

```bash
# Analyze entire lib directory
bundle exec reek lib/

# Analyze specific file
bundle exec reek lib/rails_ai_bridge/introspector.rb

# Generate detailed report
bundle exec reek lib/ --format json > reek_report.json
```

## Configuration

Reek uses `.reek.yml` for configuration (if present). Common configurations include:

- Excluding specific detectors for certain files
- Adjusting smell thresholds
- Ignoring specific method patterns

## Key Smells Reek Detects

| Smell | Description | Typical Fix |
|-------|-------------|-------------|
| `DuplicateMethodCall` | Same method called multiple times | Extract variable or method |
| `TooManyStatements` | Method has too many lines | Extract private methods |
| `TooManyInstanceVariables` | Class has too many instance variables | Consider splitting class |
| `FeatureEnvy` | Method uses another object more than self | Move method to other class |
| `UtilityFunction` | Method doesn't use self | Consider making class method |
| `ControlParameter` | Parameter controls method flow | Split method or use polymorphism |

## Continuous Integration

Reek runs automatically in CI. To disable locally:

```bash
REEK=false bundle exec rspec
```

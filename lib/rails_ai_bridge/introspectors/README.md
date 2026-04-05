# `lib/rails_ai_bridge/introspectors`

This folder contains the built-in introspectors.

## Contract

Each introspector should:

- be a small PORO
- accept the Rails app in `initialize(app)`
- expose a single public `#call`
- return a `Hash`
- avoid raising for expected app-shape differences

## Design intent

Introspectors are the data collection layer. They should not format output for AI clients and should not know about MCP transport concerns.

## Registration

Built-ins are mapped in `lib/rails_ai_bridge/introspector.rb`.

Host apps or companion gems can add new introspectors with:

```ruby
RailsAiBridge.configure do |config|
  config.additional_introspectors[:billing] = MyCompany::BillingIntrospector
  config.introspectors << :billing
end
```

## Good boundaries

An introspector should answer one domain question well:

- schema
- models
- non_ar_models (plain Ruby classes under `app/models` that are not ActiveRecord)
- routes
- controllers
- tests
- conventions

If a new file starts mixing multiple domains, split it before it grows.

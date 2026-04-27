# `spec/lib/rails_ai_bridge`

This folder contains the main unit and integration coverage for the gem runtime.

## What lives here

- configuration specs
- introspector and introspector-specific specs
- MCP tool specs
- resource specs
- server and middleware specs
- serializer specs
- generator-facing behavior that is exercised close to the runtime code

## Testing philosophy

Prefer narrow behavioral specs over broad implementation coupling.

Examples:

- use tool specs to verify tool output contracts
- use generator specs to prove install flow behavior
- use integration specs when custom extension seams must work together

## New seams introduced in this area

The current architecture relies on tests around:

- `ContextProvider` for snapshot and section caching
- custom extension registration through configuration
- shared HTTP transport behavior via `HttpTransportApp`

If you change one of those boundaries, update the corresponding spec first.

## Coverage threshold and gaps

The suite uses **code quality standards** via Reek, Rubocop, and security tooling.
For how to list files under quality thresholds and a living action backlog, see
[`docs/COVERAGE.md`](../../../docs/COVERAGE.md).

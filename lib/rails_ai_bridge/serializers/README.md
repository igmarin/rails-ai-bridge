# `lib/rails_ai_bridge/serializers`

This folder contains the output layer for generated bridge files.

## Responsibilities

Serializers turn introspection hashes into assistant-specific files such as:

- `CLAUDE.md`
- `AGENTS.md`
- `.cursorrules`
- `.windsurfrules`
- `.github/copilot-instructions.md`
- split rule files under assistant-specific subfolders

## Boundaries

Serializers should:

- format data, not collect it
- stay independent from MCP transport code
- respect assistant-specific limits and conventions
- keep compact vs full behavior explicit

## Entry point

`context_file_serializer.rb` is the orchestrator for writing files and split-rule support files.

## Adding a serializer

If you add support for a new AI client:

1. add the serializer class
2. register its main output in `ContextFileSerializer::FORMAT_MAP`
3. add split-rule support only if the target client benefits from path-scoped or always-on files
4. cover unchanged-file behavior in specs

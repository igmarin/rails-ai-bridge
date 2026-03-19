# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| unreleased fork | :white_check_mark: |
| 0.7.x   | :white_check_mark: |
| 0.6.x   | :white_check_mark: |
| < 0.6   | :x:                |

## Reporting a Vulnerability

This fork is maintained by **Ismael Marin**. If you discover a security vulnerability in this fork of `rails-ai-context`, please report it responsibly:

1. **Do NOT open a public GitHub issue.**
2. Email **ismael.marin@gmail.com** with:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
3. Include the affected version, Ruby version, Rails version, and whether the issue requires the HTTP transport or `auto_mount`.
4. You will receive a best-effort response as quickly as possible.

## Security Design

- All MCP tools are **read-only** and never modify your application or database.
- Code search (`rails_search_code`) uses `Open3.capture2` with array arguments to prevent shell injection.
- File paths are validated against path traversal attacks, and invalid regex input now returns a controlled tool response in the Ruby fallback path.
- Credentials and secret values are **never** exposed — only key names are introspected.
- The gem does not make any outbound network requests.
- The main risk is **information exposure**, not mutation: schema names, routes, controller structure, and code excerpts may still be sensitive in some environments.

## Operational Security Guidance

- Prefer **stdio** transport for local development and AI-assisted editing.
- If you enable HTTP transport, keep it bound to `127.0.0.1` unless you add your own network isolation and authentication controls.
- Do **not** expose `auto_mount` on public or shared production surfaces without an explicit threat model review.
- Treat generated files such as `AGENTS.md`, `CLAUDE.md`, `.cursorrules`, and `.ai-context.json` as internal engineering documentation.

# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 0.7.x   | :white_check_mark: |
| 0.6.x   | :white_check_mark: |
| < 0.6   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in rails-ai-context, please report it responsibly:

1. **Do NOT open a public GitHub issue.**
2. Email **crisjosephnahine@gmail.com** with:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
3. You will receive a response within 48 hours.
4. A fix will be released as a patch version as soon as possible.

## Security Design

- All MCP tools are **read-only** and never modify your application or database.
- Code search (`rails_search_code`) uses `Open3.capture2` with array arguments to prevent shell injection.
- File paths are validated against path traversal attacks.
- Credentials and secret values are **never** exposed — only key names are introspected.
- The gem does not make any outbound network requests.

# Registry Resolution

The registry resolution system enables loading and resolving skill packs from git
repositories with priority-based conflict resolution.

## Overview

The registry system allows you to:

- Load skill packs from remote git repositories
- Resolve skills and agents across multiple packs with priority rules
- Override remote packs with local registries
- Auto-detect framework-specific packs (Rails, Hanami)

## Priority Rules

Packs are loaded with the following priority levels (lower value = higher priority):

| Priority | Pack Type | Example |
|----------|-----------|---------|
| 0 | Local registries | `local_registry_paths` |
| 10 | Framework packs | `rails`, `hanami` |
| 20 | Core pack | `core` |
| 30 | Other packs | Custom packs |

Higher priority packs override skills/agents from lower priority packs when names conflict.

## Configuration

Configure the registry in your Rails application initializer:

```ruby
# config/initializers/rails_ai_bridge.rb
RailsAiBridge.configure do |config|
  config.registry.registry_manifest_path = 'config/rails_ai_bridge_registry.json'
  config.registry.skill_cache_dir = '~/.rails-ai-bridge/cache'
  config.registry.skill_packs = nil # Auto-detect, or specify e.g. ['rails', 'core']
  config.registry.local_registry_paths = [] # Add local override paths
end
```

### Configuration Options

- **registry_manifest_path**: Path to the registry manifest JSON file
  (default: `config/rails_ai_bridge_registry.json`)
- **skill_cache_dir**: Directory for caching git repositories
  (default: `~/.rails-ai-bridge/cache`, override with `RAILS_AI_BRIDGE_CACHE_DIR`)
- **skill_packs**: Explicit pack names to load, or `nil` for auto-detection
- **local_registry_paths**: Array of local directory paths containing skill packs
  (priority 0)

## Registry Manifest Structure

The registry manifest is a JSON file defining available packs:

```json
{
  "version": "1.0",
  "default_stack": ["core"],
  "packs": {
    "rails": {
      "source": "igmarin/ruby-rails-skills",
      "tile": "tile.json",
      "always_loaded": false,
      "depends_on": ["core"]
    },
    "core": {
      "source": "igmarin/ruby-core-skills",
      "tile": "tile.json",
      "always_loaded": true,
      "depends_on": []
    },
    "hanami": {
      "source": "igmarin/ruby-hanami-skills",
      "tile": "tile.json",
      "always_loaded": false,
      "depends_on": ["core"]
    }
  }
}
```

### Manifest Fields

- **version**: Schema version string
- **default_stack**: Pack names to load when no framework is detected
- **packs**: Object mapping pack names to definitions
  - **source**: GitHub repository in `owner/repo` format
  - **tile**: Path to tile manifest within the repository
  - **always_loaded**: Boolean, whether to always load this pack
  - **depends_on**: Array of pack names this pack depends on

## Usage

### Rake Tasks

List all available skills:

```bash
rails ai:registry:list_skills
```

Resolve and print a specific skill:

```bash
rails ai:registry:resolve_skill[pack,name]
# or
PACK=pack NAME=skill rails ai:registry:resolve_skill
```

### MCP Tools

When using the MCP server, the following tools are available:

- **rails_list_skills**: List all available skills across loaded packs
- **rails_list_agents**: List all available agents across loaded packs
- **rails_list_packs**: List loaded packs with priorities

Example MCP tool call:

```json
{
  "name": "rails_list_skills",
  "arguments": {}
}
```

## Framework Auto-Detection

When `skill_packs` is `nil`, the system auto-detects the framework:

- **Rails detected**: Loads `rails` pack (priority 10)
- **Hanami detected**: Loads `hanami` pack (priority 10)
- **No framework detected**: Loads `default_stack` packs

Framework detection is performed by the `PackDetector` class.

## Local Registries

Local registries allow you to override remote packs with local development versions:

```ruby
config.registry.local_registry_paths = [
  '/path/to/local/skills',
  '/path/to/another/local/registry'
]
```

Each local registry directory must contain a `tile.json` manifest. Local registries
always have priority 0 (highest).

## Cache Directory

Git repositories are cached in `~/.rails-ai-bridge/cache` by default. Override with
the `RAILS_AI_BRIDGE_CACHE_DIR` environment variable:

```bash
export RAILS_AI_BRIDGE_CACHE_DIR=/custom/cache/path
```

Cache keys are computed from source strings using SHA256 hashing to prevent collisions.

## Skill Resolution

Skills are resolved by name across all loaded packs, with priority rules:

1. Local registries (priority 0) are checked first
2. Framework packs (priority 10) are checked next
3. Core pack (priority 20) is checked next
4. Other packs (priority 30) are checked last

The first matching skill is returned. Deprecation redirects are handled transparently.

## Deprecation Handling

Deprecated skills are defined in pack tile manifests and can redirect to new skill
names or include removal version information. The resolver automatically follows
deprecation redirects when resolving skills.

## Dependency Validation

The resolver validates that all pack dependencies are satisfied among loaded packs. Warnings are logged for missing dependencies.

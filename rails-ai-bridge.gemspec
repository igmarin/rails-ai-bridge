# frozen_string_literal: true

require_relative 'lib/rails_ai_bridge/version'

Gem::Specification.new do |spec|
  spec.name          = 'rails-ai-bridge'
  spec.version       = RailsAiBridge::VERSION
  spec.authors       = ['Ismael Marin']
  spec.email         = ['ismael.marin@gmail.com']

  spec.summary       = 'Maps a Rails app so AI assistants stop guessing.'
  spec.description   = 'Maps a Rails app so assistants stop guessing — static context files and a read-only MCP server.'

  spec.homepage      = 'https://github.com/igmarin/rails-ai-bridge'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.2.0'
  spec.required_rubygems_version = '>= 3.4'

  spec.metadata['homepage_uri']      = spec.homepage
  spec.metadata['source_code_uri']   = "#{spec.homepage}/tree/main"
  spec.metadata['changelog_uri']     = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['documentation_uri'] = "#{spec.homepage}#readme"
  spec.metadata['bug_tracker_uri']   = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.post_install_message = <<~MSG
    rails-ai-bridge installed! Quick start:
      rails generate rails_ai_bridge:install
      rails ai:bridge          # generate bridge files (compact mode)
      rails ai:bridge:full     # full dump (good for small apps)
      rails ai:serve           # start MCP server for Claude Code / Cursor
  MSG

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Core dependencies
  spec.add_dependency 'mcp', '>= 1.0', '< 2.0' # Official MCP Ruby SDK (1.x stable)
  spec.add_dependency 'railties', '>= 7.1', '< 10.0'
  spec.add_dependency 'thor', '>= 1.0', '< 3.0'
  spec.add_dependency 'zeitwerk', '~> 2.6' # Autoloading

  # Semantic code analysis via Shopify's rubydex
  spec.add_dependency 'rubydex', '~> 0.3.0'
end

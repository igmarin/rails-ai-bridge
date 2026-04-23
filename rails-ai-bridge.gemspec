# frozen_string_literal: true

require_relative 'lib/rails_ai_bridge/version'

Gem::Specification.new do |spec|
  spec.name          = 'rails-ai-bridge'
  spec.version       = RailsAiBridge::VERSION
  spec.authors       = ['Ismael Marin']
  spec.email         = ['ismael.marin@gmail.com']

  spec.summary       = 'Senior-grade AI context and semantic model tiering for Ruby on Rails.'
  spec.description   = <<~DESC.gsub(/\s+/, ' ').strip
    Rails-AI-Bridge introspects your Rails application and exposes structure to AI assistants via
    static context files and a live Model Context Protocol (MCP) server. It classifies Active Record
    models semantically (Core, Join, Supporting), optionally surfaces non-ActiveRecord Ruby classes
    under app/models (tagged POJO/Service), and integrates with editors and assistants such as
    Claude, Gemini, Cursor, and Windsurf.
  DESC

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
  spec.add_dependency 'mcp', '>= 0.10', '< 0.13' # Official MCP Ruby SDK
  spec.add_dependency 'railties', '>= 7.1', '< 9.0'
  spec.add_dependency 'thor', '>= 1.0', '< 3.0'
  spec.add_dependency 'zeitwerk', '~> 2.6' # Autoloading

  # Development dependencies are specified in Gemfile
end

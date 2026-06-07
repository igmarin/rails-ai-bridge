# frozen_string_literal: true

require 'fileutils'

unless defined?(ASSISTANT_TABLE)
  ASSISTANT_TABLE = <<~TABLE
    AI Assistant       Bridge File                           Command
    --                 --                                    --
    Claude Code        CLAUDE.md + .claude/rules/            rails ai:bridge:claude
    OpenAI Codex       AGENTS.md + .codex/README.md          rails ai:bridge:codex
    Cursor             .cursorrules + .cursor/rules/         rails ai:bridge:cursor
    Windsurf           .windsurfrules + .windsurf/rules/     rails ai:bridge:windsurf
    GitHub Copilot     .github/copilot-instructions.md       rails ai:bridge:copilot
    JSON (generic)     .ai-context.json                      rails ai:bridge:json
    Gemini             GEMINI.md                             rails ai:bridge:gemini
  TABLE
end

module RailsAiBridge
  # Helper methods for Rake tasks — extracted here to avoid polluting global Object.
  module RakeHelpers
    TRUTHY_ENV_VALUES = %w[1 true yes y].freeze unless defined?(TRUTHY_ENV_VALUES)

    # Prints the result hash from +generate_context+ to stdout.
    #
    # @param result [Hash{Symbol => Array<String>}] keys +:written+ and +:skipped+
    # @return [void]
    def self.print_result(result)
      result[:written].each { |f| puts "  ✅ #{f}" }
      result[:skipped].each { |f| puts "  ⏭️  #{f} (unchanged)" }
    end

    # Overrides the context mode from the +CONTEXT_MODE+ env var if set.
    #
    # @return [void]
    def self.apply_context_mode_override
      return unless ENV['CONTEXT_MODE']

      mode = ENV['CONTEXT_MODE'].to_sym
      RailsAiBridge.configuration.context_mode = mode
      puts "📐 Context mode: #{mode}"
    end

    # Returns :prompt when CONFIRM is one of "1", "true", "yes", "y" so rake tasks
    # ask before overwriting changed files. CONFIRM=0 or CONFIRM=false stays silent.
    # Resolves the conflict strategy from the +CONFIRM+ env var.
    #
    # @return [:prompt, :overwrite] +:prompt+ when CONFIRM is truthy, +:overwrite+ otherwise
    def self.conflict_strategy
      TRUTHY_ENV_VALUES.include?(ENV['CONFIRM'].to_s.downcase.strip) ? :prompt : :overwrite
    end

    # Runs pre-generation diagnostic checks when +CHECK+ env var is truthy.
    # Aborts the task if any check fails.
    #
    # @return [void]
    def self.run_pre_generation_checks
      return unless TRUTHY_ENV_VALUES.include?(ENV['CHECK'].to_s.downcase.strip)

      puts '🩺 Running pre-generation diagnostic checks (CHECK=1)...'
      result = RailsAiBridge::Doctor.new.run
      failed_checks = result[:checks].select { |c| c.status == :fail }

      if failed_checks.any?
        puts '❌ Diagnostics failed! Cannot regenerate bridge files.'
        failed_checks.each do |check|
          puts "  ❌ #{check.name}: #{check.message}"
          puts "     Fix: #{check.fix}" if check.fix
        end
        abort 'Pre-generation checks failed.'
      else
        puts '✅ Diagnostics passed. Proceeding with file generation...'
      end
    end
  end
end

namespace :ai do
  desc 'Generate AI bridge files (CLAUDE.md, .cursorrules, .windsurfrules, .github/copilot-instructions.md)'
  task bridge: :environment do
    require 'rails_ai_bridge'

    RailsAiBridge::RakeHelpers.apply_context_mode_override
    RailsAiBridge::RakeHelpers.run_pre_generation_checks

    puts "🔍 Introspecting #{Rails.application.class.module_parent_name}..."

    puts '📝 Writing bridge files...'
    result = RailsAiBridge.generate_context(
      format: :all, split_rules: true,
      on_conflict: RailsAiBridge::RakeHelpers.conflict_strategy
    )

    RailsAiBridge::RakeHelpers.print_result(result)
    puts ''
    puts 'Done! Your AI assistants now understand your Rails app.'
    puts 'Commit these files so your whole team benefits.'
    puts ''
    puts ASSISTANT_TABLE
  end

  desc 'Generate AI bridge output in a specific format (claude, codex, cursor, windsurf, copilot, json)'
  task :bridge_for, [:format] => :environment do |_t, args|
    require 'rails_ai_bridge'

    RailsAiBridge::RakeHelpers.apply_context_mode_override
    RailsAiBridge::RakeHelpers.run_pre_generation_checks

    format = (args[:format] || ENV['FORMAT'] || 'claude').to_sym
    puts "🔍 Introspecting #{Rails.application.class.module_parent_name}..."

    puts "📝 Writing #{format} bridge file..."
    result = RailsAiBridge.generate_context(
      format: format, split_rules: true,
      on_conflict: RailsAiBridge::RakeHelpers.conflict_strategy
    )

    RailsAiBridge::RakeHelpers.print_result(result)
  end
end

namespace :ai do
  namespace :bridge do
    { claude: 'CLAUDE.md', codex: 'AGENTS.md', cursor: '.cursorrules', windsurf: '.windsurfrules',
      copilot: '.github/copilot-instructions.md', json: '.ai-context.json', gemini: 'GEMINI.md' }.each do |fmt, file|
      desc "Generate #{file} bridge file"
      task fmt => :environment do
        require 'rails_ai_bridge'

        RailsAiBridge::RakeHelpers.apply_context_mode_override
        RailsAiBridge::RakeHelpers.run_pre_generation_checks

        puts "🔍 Introspecting #{Rails.application.class.module_parent_name}..."
        puts "📝 Writing #{file}..."
        result = RailsAiBridge.generate_context(
          format: fmt, split_rules: true,
          on_conflict: RailsAiBridge::RakeHelpers.conflict_strategy
        )

        RailsAiBridge::RakeHelpers.print_result(result)
        puts ''
        puts 'Tip: Run `rails ai:bridge` to generate all formats at once.'
      end
    end

    desc 'Generate AI bridge files in full mode (dumps everything)'
    task full: :environment do
      require 'rails_ai_bridge'

      RailsAiBridge::RakeHelpers.apply_context_mode_override
      RailsAiBridge.configuration.context_mode = :full
      RailsAiBridge::RakeHelpers.run_pre_generation_checks

      puts "🔍 Introspecting #{Rails.application.class.module_parent_name} (full mode)..."
      puts '📝 Writing bridge files...'
      result = RailsAiBridge.generate_context(
        format: :all, split_rules: true,
        on_conflict: RailsAiBridge::RakeHelpers.conflict_strategy
      )

      RailsAiBridge::RakeHelpers.print_result(result)
      puts ''
      puts 'Done! Full bridge files generated (all details included).'
    end
  end
end

namespace :ai do
  desc 'Start the MCP server (stdio transport, for Claude Code / Cursor)'
  task serve: :environment do
    require 'rails_ai_bridge'

    RailsAiBridge.start_mcp_server(transport: :stdio)
  end

  desc 'Start the MCP server with HTTP transport'
  task serve_http: :environment do
    require 'rails_ai_bridge'

    RailsAiBridge.start_mcp_server(transport: :http)
  end
end

namespace :ai do
  desc 'Print introspection summary to stdout (useful for debugging)'
  task inspect: :environment do
    require 'rails_ai_bridge'
    require 'json'

    context = RailsAiBridge.introspect

    puts '=' * 60
    puts " #{context[:app_name]} — AI Context Summary"
    puts '=' * 60
    puts ''
    puts "Rails #{context[:rails_version]} | Ruby #{context[:ruby_version]}"
    puts ''

    puts "📦 Database: #{context[:schema][:total_tables]} tables (#{context[:schema][:adapter]})" if context[:schema] && !context[:schema][:error]

    if (context[:models] && !context[:models].is_a?(Hash)) ||
       (context[:models].is_a?(Hash) && !context[:models][:error])
      puts "🏗️  Models: #{context[:models].size}"
    end

    puts "🛤️  Routes: #{context[:routes][:total_routes]}" if context[:routes] && !context[:routes][:error]

    if context[:jobs]
      puts "⚡ Jobs: #{context[:jobs][:jobs]&.size || 0}"
      puts "📧 Mailers: #{context[:jobs][:mailers]&.size || 0}"
    end

    if context[:conventions]
      arch = context[:conventions][:architecture] || []
      puts "🏛️  Architecture: #{arch.join(', ')}" if arch.any?
    end

    puts ''
    puts ASSISTANT_TABLE
    puts ''
    puts 'Run `rails ai:bridge` to generate bridge files.'
  end
end

namespace :ai do
  desc 'Watch for changes and auto-regenerate bridge files (requires listen gem)'
  task watch: :environment do
    require 'rails_ai_bridge'

    RailsAiBridge::Watcher.new.start
  end

  desc 'Run diagnostic checks and report AI readiness score'
  task doctor: :environment do
    require 'rails_ai_bridge'

    puts '🩺 Running AI readiness diagnostics...'
    puts ''

    result = RailsAiBridge::Doctor.new.run

    result[:checks].each do |check|
      icon = { pass: '✅', warn: '⚠️ ', fail: '❌' }[check.status]
      puts "  #{icon} #{check.name}: #{check.message}"
      puts "     Fix: #{check.fix}" if check.fix
    end

    puts ''
    puts "AI Readiness Score: #{result[:score]}/100"
  end

  desc 'Run diagnostic checks and exit with non-zero status if any check fails'
  task check: :environment do
    require 'rails_ai_bridge'

    puts '🩺 Running AI readiness diagnostics...'
    puts ''

    result = RailsAiBridge::Doctor.new.run

    any_failed = false

    result[:checks].each do |check|
      icon = { pass: '✅', warn: '⚠️ ', fail: '❌' }[check.status]
      puts "  #{icon} #{check.name}: #{check.message}"
      puts "     Fix: #{check.fix}" if check.fix
      any_failed ||= (check.status == :fail)
    end

    puts ''
    puts "AI Readiness Score: #{result[:score]}/100"

    if any_failed
      puts '❌ Diagnostics failed! Please fix the errors listed above.'
      exit 1
    else
      puts '✅ Diagnostics passed.'
    end
  end
end

namespace :ai do
  namespace :skills do
    desc 'List all available skills from configured skill packs'
    task list: :environment do
      require 'rails_ai_bridge'

      resolver = RailsAiBridge::Registry.build_resolver
      unless resolver
        path = RailsAiBridge.configuration.registry.registry_manifest_path
        warn RailsAiBridge::Registry::RakePresenter.no_manifest_message(path)
        exit 1
      end

      puts RailsAiBridge::Registry::RakePresenter.new(resolver).skills_table
    end

    desc 'Resolve and print a skill by name (usage: rails "ai:skills:resolve[pack_name,skill_name]")'
    task :resolve, %i[pack name] => :environment do |_t, args|
      require 'rails_ai_bridge'

      pack_arg = args[:pack] || ENV.fetch('PACK', nil)
      name_arg = args[:name] || ENV.fetch('SKILL', nil)

      unless name_arg
        warn 'Usage: rails "ai:skills:resolve[pack_name,skill_name]"'
        warn 'Example: rails "ai:skills:resolve[rails,code-review]"'
        exit 1
      end

      resolver = RailsAiBridge::Registry.build_resolver
      unless resolver
        path = RailsAiBridge.configuration.registry.registry_manifest_path
        warn RailsAiBridge::Registry::RakePresenter.no_manifest_message(path)
        exit 1
      end

      output = RailsAiBridge::Registry::RakePresenter.new(resolver)
                                                     .resolve_skill_output(name_arg, requested_pack: pack_arg)
      puts output
      exit 1 if output.start_with?("Skill '#{name_arg}' not found")
    end

    desc 'Clear the local skill pack git cache'
    task clear_cache: :environment do
      require 'rails_ai_bridge'

      cache_dir = File.expand_path(RailsAiBridge.configuration.registry.skill_cache_dir.to_s)

      abort 'Refusing to clear cache: skill_cache_dir is empty' if cache_dir.empty?

      # Guard against misconfigured paths that could delete unrelated directories.
      dangerous_roots = [
        File.expand_path('/'),
        File.expand_path('.'),
        File.expand_path(Dir.home)
      ].map { |p| p.chomp('/') }

      abort "Refusing to clear cache from unsafe path: #{cache_dir}" if dangerous_roots.include?(cache_dir.chomp('/'))

      unless Dir.exist?(cache_dir)
        puts "Cache directory does not exist: #{cache_dir}"
        exit 0
      end

      packs = Dir.children(cache_dir).select { |entry| File.directory?(File.join(cache_dir, entry)) }
      packs.each { |entry| FileUtils.rm_rf(File.join(cache_dir, entry)) }

      RailsAiBridge::Registry.invalidate_resolver_cache!

      puts "Cleared #{packs.length} cached pack(s) from #{cache_dir}"
    end
  end
end

# frozen_string_literal: true

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
    TRUTHY_ENV_VALUES = %w[1 true yes y].freeze

    def self.print_result(result)
      result[:written].each { |f| puts "  ✅ #{f}" }
      result[:skipped].each { |f| puts "  ⏭️  #{f} (unchanged)" }
    end

    def self.apply_context_mode_override
      return unless ENV['CONTEXT_MODE']

      mode = ENV['CONTEXT_MODE'].to_sym
      RailsAiBridge.configuration.context_mode = mode
      puts "📐 Context mode: #{mode}"
    end

    # Returns :prompt when CONFIRM is one of "1", "true", "yes", "y" so rake tasks
    # ask before overwriting changed files. CONFIRM=0 or CONFIRM=false stays silent.
    def self.conflict_strategy
      TRUTHY_ENV_VALUES.include?(ENV['CONFIRM'].to_s.downcase.strip) ? :prompt : :overwrite
    end

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

      RailsAiBridge.configuration.context_mode = :full
      RailsAiBridge::RakeHelpers.apply_context_mode_override
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

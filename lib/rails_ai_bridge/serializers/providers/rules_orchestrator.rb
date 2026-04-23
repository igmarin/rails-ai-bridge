# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      require_relative '../shared_assistant_guidance'

      # Orchestrates the assembly of the compact project rules document.
      # This class takes over the responsibility of gathering and arranging
      # various sections, including shared guidance, notable gems, architecture,
      # key considerations, and models, for the compact output format.
      class RulesOrchestrator < RailsAiBridge::Serializers::Providers::Base
        # @param context [Hash] The introspection context.
        # @param config [RailsAiBridge::Configuration] The configuration object.
        def initialize(context:, config: RailsAiBridge.configuration)
          super(context: context)
          @config = config
        end

        # Renders the compact version of the Cursor rules file.
        #
        # @return [String] The generated content.
        def call
          lines = []
          # Custom header
          lines << "# #{@context[:app_name]} — Project Rules"
          lines << ''
          lines << "Rails #{@context[:rails_version]} | Ruby #{@context[:ruby_version]}"
          lines << ''
          lines.concat(SharedAssistantGuidance.compact_engineering_rules_lines)

          # Use shared sections
          lines.concat(render_stack_overview)
          lines.concat(render_notable_gems)
          lines.concat(render_architecture)
          lines.concat(render_key_considerations)

          lines << ''
          lines.concat(SharedAssistantGuidance.repo_specific_guidance_section_lines)

          lines << ''

          append_compact_cursorrules_models_section(lines, @context[:models])

          # MCP tools reference
          lines.concat(McpToolReferenceFormatter.new(context: @context).call.lines.map(&:chomp))

          # Use shared footer
          lines.concat(render_footer)

          lines.join("\n")
        end

        private

        # Renders a section for the Rails stack and overview.
        # @return [Array<String>] Markdown lines for the stack overview.
        def render_stack_overview
          return [] unless @context[:app_overview] # Ensure app_overview exists

          lines = []
          # Assume app_overview section has already been formatted by a dedicated AppOverviewFormatter
          # For RulesOrchestrator, we need to extract specific points or reformat if needed.
          # For simplicity here, just re-add basics.
          lines << '## Application Stack & Overview'
          lines << "- **Name:** `#{@context[:app_name]}`" if @context[:app_name]
          lines << "- **Rails:** `#{@context[:rails_version]}`" if @context[:rails_version]
          lines << "- **Ruby:** `#{@context[:ruby_version]}`" if @context[:ruby_version]
          lines << "- **Environment:** `#{@context[:environment]}`" if @context[:environment]
          lines << "- **Database:** `#{@context[:database_adapter]}`" if @context[:database_adapter]
          lines
        end

        # Renders a section for notable gems.
        # @return [Array<String>] Markdown lines for notable gems.
        def render_notable_gems
          return [] unless @context[:gems] && @context[:gems][:notable_gems]&.any?

          lines = ['## Notable Gems']
          @context[:gems][:notable_gems].sort_by { |g| [g[:category], g[:name]] }.each do |g|
            lines << "- `#{g[:name]}` (`#{g[:version]}`): #{g[:note]}"
          end
          lines
        end

        # Renders a section for detected architecture and conventions.
        # @return [Array<String>] Markdown lines for architecture and conventions.
        def render_architecture
          return [] unless @context[:conventions] && @context[:conventions][:architecture]&.any?

          lines = ['## Architecture & Conventions']
          @context[:conventions][:architecture].each { |a| lines << "- #{a.humanize}" }
          lines
        end

        # Renders a section for key development considerations.
        # @return [Array<String>] Markdown lines for key considerations.
        def render_key_considerations
          return [] unless @context[:tests] || @context[:config]

          lines = ['## Key Development Considerations']
          if @context[:tests] && @context[:tests][:framework]
            lines << "- **Test Framework:** `#{@context[:tests][:framework]}`"
          end
          if @context[:config] && @context[:config][:cache_store]
            lines << "- **Cache Store:** `#{@context[:config][:cache_store]}`"
          end
          lines
        end

        # Appends a compact list of key models specific to Cursor rules.
        # @param lines [Array<String>] The array of lines to append to.
        # @param models [Hash] The models context.
        def append_compact_cursorrules_models_section(lines, models)
          return unless models.is_a?(Hash) && !models[:error] && models.any?

          limit = @config.copilot_compact_model_list_limit.to_i # uses copilot limit for now
          lines << "## Models (#{models.size} total)"
          if limit <= 0
            lines << %{- _Use `rails_get_model_details(detail:"summary")` for names._}
          else
            models.keys.sort.first(limit).each do |name|
              data = models[name]
              assoc_count = (data[:associations] || []).size
              lines << "- #{name} (#{assoc_count} associations)"
            end
            remainder = models.size - limit
            lines << %{- _...#{remainder} more — `rails_get_model_details(detail:"summary")`._} if remainder.positive?
          end
          lines << ''
        end

        # @return [Array<String>] Markdown lines for the shared footer.
        def render_footer
          SharedAssistantGuidance.compact_engineering_rules_footer_lines(@context)
        end
      end
    end
  end
end

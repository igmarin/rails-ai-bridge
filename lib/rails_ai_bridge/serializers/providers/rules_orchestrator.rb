# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      require_relative '../shared_assistant_guidance'

      # Orchestrates the assembly of the compact project rules document.
      # This class takes over the responsibility of gathering and arranging
      # various sections, including shared guidance, notable gems, architecture,
      # key considerations, and models, for the compact output format.
      #
      # The class follows the Single Responsibility Principle by focusing solely
      # on document assembly and formatting, delegating data extraction to other
      # components and using composition over inheritance.
      #
      # @example Basic usage
      #   orchestrator = RulesOrchestrator.new(context: introspection_context)
      #   rules_document = orchestrator.call
      #   puts rules_document
      #
      # @example With custom configuration
      #   config = RailsAiBridge::Configuration.new
      #   config.copilot_compact_model_list_limit = 10
      #   orchestrator = RulesOrchestrator.new(context: context, config: config)
      class RulesOrchestrator < RailsAiBridge::Serializers::Providers::Base
        # Section header constants for consistency and maintainability
        # These templates ensure consistent formatting across the document
        PROJECT_RULES_HEADER = '# %s — Project Rules'
        VERSION_INFO_FORMAT = 'Rails %s | Ruby %s'

        # Hash of section headers for easy access and consistency
        # Each header follows the Markdown ## convention for sections
        SECTION_HEADERS = {
          stack_overview: '## Application Stack & Overview',
          notable_gems: '## Notable Gems',
          architecture: '## Architecture & Conventions',
          key_considerations: '## Key Development Considerations',
          models: '## Models (%d total)'
        }.freeze

        # Formatting templates for consistent output throughout the document
        # Using format strings ensures proper escaping and consistent styling
        STACK_INFO_TEMPLATES = {
          name: '- **Name:** `%s`',
          rails: '- **Rails:** `%s`',
          ruby: '- **Ruby:** `%s`',
          environment: '- **Environment:** `%s`',
          database: '- **Database:** `%s`'
        }.freeze

        # Template for individual gem entries showing name, version, and description
        GEM_ENTRY_FORMAT = '- `%s` (`%s`): %s'

        # Template for architecture and convention entries
        ARCHITECTURE_ENTRY_FORMAT = '- %s'

        # Templates for key development considerations
        CONSIDERATION_TEMPLATES = {
          test_framework: '- **Test Framework:** `%s`',
          cache_store: '- **Cache Store:** `%s`'
        }.freeze

        # Template for model entries showing name and association count
        MODEL_ENTRY_FORMAT = '- %s (%d associations)'

        # Template for overflow message when models exceed display limit
        MODELS_OVERFLOW_FORMAT = '- _...%d more — `rails_get_model_details(detail:"summary")`._'

        # Message when model limit is set to zero
        MODELS_LIMIT_ZERO_FORMAT = '- _Use `rails_get_model_details(detail:"summary")` for names._'

        # Initialize a new RulesOrchestrator instance.
        #
        # @param context [Hash] The introspection context containing application data.
        #   Expected keys include: :app_name, :rails_version, :ruby_version, :gems, :conventions, etc.
        # @param config [RailsAiBridge::Configuration] The configuration object.
        #   Uses RailsAiBridge.configuration as default if none provided.
        # @return [RulesOrchestrator] a new orchestrator instance
        def initialize(context:, config: RailsAiBridge.configuration)
          super(context: context)
          @config = config
        end

        # Renders the complete compact project rules document.
        #
        # This is the main entry point that orchestrates the assembly of all sections
        # into a coherent Markdown document suitable for AI assistants.
        #
        # @return [String] The generated Markdown content.
        # @example Generate rules document
        #   orchestrator = RulesOrchestrator.new(context: context)
        #   document = orchestrator.call
        #   File.write('RULES.md', document)
        def call
          build_document.join("\n")
        end

        private

        # Builds the complete document structure by orchestrating all sections.
        #
        # This method follows the Template Method pattern, delegating specific
        # section creation to specialized methods while maintaining overall
        # document flow and structure.
        #
        # @return [Array<String>] Array of document lines in order.
        def build_document
          lines = []

          add_header(lines)
          add_version_info(lines)
          add_shared_engineering_rules(lines)
          add_main_sections(lines)
          add_repo_guidance(lines)
          add_models_section(lines)
          add_mcp_tools_reference(lines)
          add_footer(lines)

          lines
        end

        # Adds document header with application name.
        #
        # Uses the PROJECT_RULES_HEADER constant for consistent formatting.
        #
        # @param lines [Array<String>] Document lines array to modify.
        # @return [void]
        def add_header(lines)
          lines << format(PROJECT_RULES_HEADER, @context[:app_name])
          lines << ''
        end

        # Adds Rails and Ruby version information.
        #
        # Uses the VERSION_INFO_FORMAT constant for consistent formatting.
        #
        # @param lines [Array<String>] Document lines array to modify.
        # @return [void]
        def add_version_info(lines)
          lines << format(VERSION_INFO_FORMAT, @context[:rails_version], @context[:ruby_version])
          lines << ''
        end

        # Adds shared engineering rules section from SharedAssistantGuidance.
        #
        # @param lines [Array<String>] Document lines array to modify.
        # @return [void]
        def add_shared_engineering_rules(lines)
          lines.concat(SharedAssistantGuidance.compact_engineering_rules_lines)
        end

        # Adds main content sections (stack, gems, architecture, considerations).
        #
        # This method groups the core application information sections.
        #
        # @param lines [Array<String>] Document lines array to modify.
        # @return [void]
        def add_main_sections(lines)
          lines.concat(render_stack_overview)
          lines.concat(render_notable_gems)
          lines.concat(render_architecture)
          lines.concat(render_key_considerations)
        end

        # Adds repository-specific guidance section.
        #
        # @param lines [Array<String>] Document lines array to modify.
        # @return [void]
        def add_repo_guidance(lines)
          lines << ''
          lines.concat(SharedAssistantGuidance.repo_specific_guidance_section_lines)
        end

        # Adds models section with compact formatting.
        #
        # @param lines [Array<String>] Document lines array to modify.
        # @return [void]
        def add_models_section(lines)
          lines << ''
          append_compact_cursorrules_models_section(lines, @context[:models])
        end

        # Adds MCP tools reference section.
        #
        # Delegates to McpToolReferenceFormatter for tool documentation.
        #
        # @param lines [Array<String>] Document lines array to modify.
        # @return [void]
        def add_mcp_tools_reference(lines)
          mcp_content = McpToolReferenceFormatter.new(context: @context).call
          lines.concat(mcp_content.lines.map(&:chomp))
        end

        # Adds shared footer section.
        #
        # @param lines [Array<String>] Document lines array to modify.
        # @return [void]
        def add_footer(lines)
          lines.concat(render_footer)
        end

        # Renders a section for the Rails stack and overview information.
        #
        # Includes application name, Rails version, Ruby version, environment,
        # and database adapter when available.
        #
        # @return [Array<String>] Markdown lines for the stack overview.
        def render_stack_overview
          return [] unless @context[:app_overview]

          lines = [SECTION_HEADERS[:stack_overview]]
          lines << format(STACK_INFO_TEMPLATES[:name], @context[:app_name]) if @context[:app_name]
          lines << format(STACK_INFO_TEMPLATES[:rails], @context[:rails_version]) if @context[:rails_version]
          lines << format(STACK_INFO_TEMPLATES[:ruby], @context[:ruby_version]) if @context[:ruby_version]
          lines << format(STACK_INFO_TEMPLATES[:environment], @context[:environment]) if @context[:environment]
          lines << format(STACK_INFO_TEMPLATES[:database], @context[:database_adapter]) if @context[:database_adapter]
          lines
        end

        # Renders a section for notable gems with their versions and descriptions.
        #
        # Gems are sorted by category and name for consistent ordering.
        #
        # @return [Array<String>] Markdown lines for notable gems.
        def render_notable_gems
          return [] unless notable_gems?

          lines = [SECTION_HEADERS[:notable_gems]]
          sorted_gems.each do |gem|
            lines << format(GEM_ENTRY_FORMAT, gem[:name], gem[:version], gem[:note])
          end
          lines
        end

        # Renders a section for detected architecture and conventions.
        #
        # Each architecture item is humanized for better readability.
        #
        # @return [Array<String>] Markdown lines for architecture and conventions.
        def render_architecture
          return [] unless architecture?

          lines = [SECTION_HEADERS[:architecture]]
          @context[:conventions][:architecture].each do |arch|
            lines << format(ARCHITECTURE_ENTRY_FORMAT, arch.humanize)
          end
          lines
        end

        # Renders a section for key development considerations.
        #
        # Includes test framework and cache store information when available.
        #
        # @return [Array<String>] Markdown lines for key considerations.
        def render_key_considerations
          return [] unless considerations?

          lines = [SECTION_HEADERS[:key_considerations]]

          lines << format(CONSIDERATION_TEMPLATES[:test_framework], @context[:tests][:framework]) if test_framework_present?

          lines << format(CONSIDERATION_TEMPLATES[:cache_store], @context[:config][:cache_store]) if cache_store_present?

          lines
        end

        # Appends a compact list of key models specific to Cursor rules format.
        #
        # Limits the number of models displayed based on configuration and
        # provides a reference for viewing additional models.
        #
        # @param lines [Array<String>] The array of lines to append to.
        # @param models [Hash] The models context with model names as keys.
        # @return [void]
        def append_compact_cursorrules_models_section(lines, models)
          return unless valid_models?(models)

          lines << format(SECTION_HEADERS[:models], models.size)

          if model_list_limit <= 0
            lines << MODELS_LIMIT_ZERO_FORMAT
          else
            add_model_entries(lines, models)
            add_overflow_message(lines, models) if overflow?(models)
          end

          lines << ''
        end

        # Returns shared footer lines from SharedAssistantGuidance.
        #
        # @return [Array<String>] Markdown lines for the shared footer.
        def render_footer
          SharedAssistantGuidance.compact_engineering_rules_footer_lines(@context)
        end

        # Helper methods for better single responsibility and readability

        # Checks if notable gems are available in the context.
        #
        # @return [Boolean] true if notable gems exist and contain data
        def notable_gems?
          @context.dig(:gems, :notable_gems)&.any? || false
        end

        # Checks if architecture information is available in the context.
        #
        # @return [Boolean] true if architecture exists and contains data
        def architecture?
          @context.dig(:conventions, :architecture)&.any? || false
        end

        # Checks if key considerations are available.
        #
        # Validates that test or config data exists and is properly structured.
        #
        # @return [Boolean] true if considerations exist
        def considerations?
          (@context[:tests] || @context[:config]) && valid_considerations_data?
        end

        # Checks if test framework information is present and valid.
        #
        # @return [Boolean] true if test framework exists
        def test_framework_present?
          @context.dig(:tests, :framework).present? || false
        end

        # Checks if cache store information is present and valid.
        #
        # @return [Boolean] true if cache store exists
        def cache_store_present?
          @context.dig(:config, :cache_store).present? || false
        end

        # Returns sorted notable gems by category and name.
        #
        # Provides consistent ordering and handles missing category/name
        # values gracefully to prevent sorting errors.
        #
        # @return [Array<Hash>] sorted gems array, empty if no gems available
        def sorted_gems
          return [] unless notable_gems?

          @context.dig(:gems, :notable_gems).sort_by { |gem| [gem[:category] || '', gem[:name] || ''] }
        rescue TypeError, ArgumentError => error
          Rails.logger.warn "Failed to sort notable gems: #{error.message}" if defined?(Rails.logger)
          []
        end

        # Validates models hash structure and content.
        #
        # Ensures models is a hash, has no error flag, and contains data.
        #
        # @param models [Hash] models context to validate
        # @return [Boolean] true if models are valid
        def valid_models?(models)
          return false unless models.is_a?(Hash)
          return false if models[:error]
          return false unless models.any?

          true
        end

        # Returns the model list limit from configuration.
        #
        # Provides a safe default value if configuration is invalid.
        #
        # @return [Integer] model list limit (defaults to 5 on error)
        def model_list_limit
          @config.copilot_compact_model_list_limit.to_i
        rescue TypeError, NoMethodError
          5 # Safe default
        end

        # Adds model entries to the lines array with association counts.
        #
        # Safely calculates association counts and formats model entries.
        #
        # @param lines [Array<String>] document lines to modify
        # @param models [Hash] models context containing model data
        # @return [void]
        def add_model_entries(lines, models)
          models.keys.sort.first(model_list_limit).each do |model_name|
            model_data = models[model_name]
            assoc_count = calculate_association_count(model_data)
            lines << format(MODEL_ENTRY_FORMAT, model_name, assoc_count)
          end
        rescue TypeError, ArgumentError => error
          Rails.logger.warn "Failed to add model entries: #{error.message}" if defined?(Rails.logger)
        end

        # Checks if there are more models than the display limit.
        #
        # @param models [Hash] models context to check
        # @return [Boolean] true if overflow exists
        def overflow?(models)
          models.size > model_list_limit
        rescue TypeError, NoMethodError
          false
        end

        # Adds overflow message for remaining models beyond the limit.
        #
        # @param lines [Array<String>] document lines to modify
        # @param models [Hash] models context for overflow calculation
        # @return [void]
        def add_overflow_message(lines, models)
          remainder = models.size - model_list_limit
          lines << format(MODELS_OVERFLOW_FORMAT, remainder) if remainder.positive?
        rescue TypeError, ArgumentError => error
          Rails.logger.warn "Failed to add overflow message: #{error.message}" if defined?(Rails.logger)
        end

        # Validates that considerations data is properly structured.
        #
        # Ensures test or config data responds to [] method for safe access.
        #
        # @return [Boolean] true if data is valid
        def valid_considerations_data?
          return true if @context[:tests].respond_to?(:[])
          return true if @context[:config].respond_to?(:[])

          false
        end

        # Calculates association count safely from model data.
        #
        # Handles nil values and non-array associations gracefully.
        #
        # @param model_data [Hash] model data hash containing associations
        # @return [Integer] association count (0 if invalid data)
        def calculate_association_count(model_data)
          return 0 unless model_data.is_a?(Hash)
          return 0 unless model_data[:associations].is_a?(Array)

          model_data[:associations].size
        end
      end
    end
  end
end

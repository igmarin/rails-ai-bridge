# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetGems < BaseTool
      tool_name "rails_get_gems"
      description "Analyze the app's Gemfile.lock to identify notable gems, their categories (auth, jobs, frontend, API, database, testing, deploy), and what they mean for the app's architecture."

      input_schema(
        properties: {
          category: {
            type: "string",
            enum: %w[auth jobs frontend api database files testing deploy all],
            description: "Filter by category. Default: all."
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      def self.call(category: "all", server_context: nil)
        gems = cached_section(:gems)
        return text_response("Gem introspection not available. Add :gems to introspectors.") unless gems
        return text_response("Gem introspection failed: #{gems[:error]}") if gems[:error]

        formatter = ResponseFormatter.new(gems, category: category)
        text_response(formatter.format)
      end

      # @private
      class ResponseFormatter
        def initialize(gems_data, category:)
          @gems_data = gems_data
          @category = category
          @notable = filter_notable_gems
        end

        def format
          lines = [ "# Gem Analysis", "" ]
          lines << "Total gems: #{@gems_data[:total_gems]}"
          lines << ""

          if @notable.any?
            current_cat = nil
            @notable.sort_by { |g| [ g[:category], g[:name] ] }.each do |g|
              if g[:category] != current_cat
                current_cat = g[:category]
                lines << "" << "## #{current_cat.capitalize}"
              end
              lines << "- **#{g[:name]}** (#{g[:version]}): #{g[:note]}"
            end
          else
            lines << "_No notable gems found#{" in category '#{@category}'" unless @category == 'all'}._"
          end

          lines.join("\n")
        end

        private

        def filter_notable_gems
          notable = @gems_data[:notable_gems] || []
          @category == "all" ? notable : notable.select { |g| g[:category] == @category }
        end
      end
    end
  end
end

# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the DevOps section with Puma config and deployment info.
      class DevopsFormatter < Base
        # @return [String, nil]
        def call
          data = context[:devops]
          return unless data
          return if data[:error]

          lines = [ "## DevOps" ]
          if data[:puma]
            lines << "### Puma"
            lines << "- Threads: #{data[:puma][:threads_min]}-#{data[:puma][:threads_max]}" if data[:puma][:threads_min]
            lines << "- Workers: #{data[:puma][:workers]}" if data[:puma][:workers]
          end
          lines << "- Deployment: #{data[:deployment]}" if data[:deployment]
          if data[:docker]
            lines << "- Docker: #{data[:docker][:multi_stage] ? 'multi-stage' : 'single-stage'} build"
          end
          lines.join("\n") if lines.size > 1
        end
      end
    end
  end
end

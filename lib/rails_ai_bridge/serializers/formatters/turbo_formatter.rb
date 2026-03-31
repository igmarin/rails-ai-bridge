# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Hotwire/Turbo section with frames, streams, and broadcasts.
      class TurboFormatter < Base
        # @return [String, nil]
        def call
          data = context[:turbo]
          return unless data
          return if data[:error]
          return if data[:turbo_frames]&.empty? && data[:turbo_streams]&.empty? && data[:model_broadcasts]&.empty?

          lines = [ "## Hotwire / Turbo" ]
          if data[:turbo_frames]&.any?
            lines << "### Turbo Frames"
            data[:turbo_frames].each { |f| lines << "- `#{f[:id]}` in #{f[:file]}" }
          end
          if data[:turbo_streams]&.any?
            lines << "### Turbo Stream Templates"
            data[:turbo_streams].each { |t| lines << "- `#{t}`" }
          end
          if data[:model_broadcasts]&.any?
            lines << "### Model Broadcasts"
            data[:model_broadcasts].each { |b| lines << "- `#{b[:model]}`: #{b[:methods].join(', ')}" }
          end
          lines.join("\n")
        end
      end
    end
  end
end

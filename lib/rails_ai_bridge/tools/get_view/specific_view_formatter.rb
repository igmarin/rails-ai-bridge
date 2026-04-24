# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class GetView
      # Formats a detailed analysis of a specific view file.
      class SpecificViewFormatter
        # @param analysis [Hash] The detailed analysis of the view file.
        # @return [String] The formatted specific view output.
        def call(analysis)
          lines = ["# View: #{analysis[:path]}", '']
          lines << "- Template engine: #{analysis[:template_engine]}" if analysis[:template_engine]
          lines << "- Partial: #{analysis[:partial] ? 'yes' : 'no'}"
          lines << "- Renders: #{analysis[:renders].join(', ')}" if analysis[:renders].any?
          lines << "- Turbo frames: #{analysis[:turbo_frames].join(', ')}" if analysis[:turbo_frames].any?
          lines << "- Stimulus controllers: #{analysis[:stimulus_controllers].join(', ')}" if analysis[:stimulus_controllers].any?
          lines << "- Stimulus actions: #{analysis[:stimulus_actions].join(', ')}" if analysis[:stimulus_actions].any?
          lines << ''
          lines << '## Source'
          lines << '```erb'
          lines << analysis[:content].rstrip
          lines << '```'
          lines.join("\n")
        end
      end
    end
  end
end

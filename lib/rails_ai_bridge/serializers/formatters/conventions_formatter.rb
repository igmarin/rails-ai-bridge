# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Formatters
      # Renders the Project Structure section from directory counts.
      class ConventionsFormatter < Base
        # @return [String, nil]
        def call
          conv = context[:conventions]
          return unless conv
          return unless conv[:directory_structure]&.any?

          lines = [ "## Project Structure" ]
          conv[:directory_structure].sort.each do |dir, count|
            lines << "- `#{dir}/` — #{count} files"
          end
          lines.join("\n")
        end
      end
    end
  end
end

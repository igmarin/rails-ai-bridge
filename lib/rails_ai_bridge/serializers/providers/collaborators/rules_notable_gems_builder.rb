# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      module Collaborators
        # Builds notable gem lines for compact rules output.
        class RulesNotableGemsBuilder
          # Heading used for the notable gems section.
          SECTION_HEADER = '## Notable Gems'

          # Format string for one notable gem row.
          GEM_ENTRY_FORMAT = '- `%s` (`%s`): %s'

          # @param gems [Hash, nil] gems context payload
          def initialize(gems)
            @gems = gems
          end

          # @return [Array<String>] notable gem lines, or empty when no gems qualify
          def call
            GemEntries.new(notable_gems.sorted, SECTION_HEADER, GEM_ENTRY_FORMAT).to_a
          end

          private

          def notable_gems
            NotableGemCollection.new(@gems)
          end

          # Formats the complete notable gems section.
          class GemEntries
            # @param gems [Array<Hash>] sorted notable gem payloads
            # @param section_header [String] section heading
            # @param entry_format [String] row format
            def initialize(gems, section_header, entry_format)
              @gems = gems
              @section_header = section_header
              @entry_format = entry_format
            end

            # @return [Array<String>] formatted section lines
            def to_a
              return [] if @gems.empty?

              [@section_header, *@gems.map { |gem| GemEntry.new(gem, @entry_format).to_s }]
            end
          end

          # Extracts notable gems from supported context keys.
          class NotableGemCollection
            # @param gems [Hash, nil] Gems context payload
            def initialize(gems)
              @gems = gems
            end

            # @return [Array<Hash>] entries sorted by category and name
            def sorted
              entries.sort_by { |gem| NotableGemSortKey.new(gem).to_a }
            end

            private

            def entries
              return [] unless @gems.is_a?(Hash) && !@gems[:error]

              normalized_entries.grep(Hash)
            end

            def normalized_entries
              raw_entries.is_a?(Hash) ? [raw_entries] : Array(raw_entries)
            end

            def raw_entries
              @raw_entries ||= [@gems[:notable_gems], @gems[:notable], @gems[:detected]].find(&:present?)
            end
          end

          # Builds a stable sort key for notable gem entries.
          class NotableGemSortKey
            # @param gem [Hash] Notable gem payload
            def initialize(gem)
              @gem = gem
            end

            # @return [Array<String>] Sort key of category then name
            def to_a
              [@gem[:category] || '', @gem[:name] || '']
            end
          end

          # Formats one notable gem row.
          class GemEntry
            # @param gem [Hash] Notable gem payload
            # @param format_string [String] row format
            def initialize(gem, format_string)
              @gem = gem
              @format_string = format_string
            end

            # @return [String] formatted gem row
            def to_s
              format(@format_string, @gem[:name], @gem[:version], @gem[:note])
            end
          end
        end
      end
    end
  end
end

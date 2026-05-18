# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    class ModelIntrospector
      # Extracts source-level macros from an ActiveRecord model's source file.
      #
      # Scans the model source for Rails macros such as +has_secure_password+,
      # +encrypts+, +normalizes+, Active Storage attachments, Action Text,
      # Turbo broadcasts, token generators, serialization, store accessors,
      # and delegations.
      class SourceMacroExtractor
        # @param source [String] the Ruby source code of the model file
        def initialize(source)
          @source = source
        end

        # @return [Hash] detected macros (empty arrays removed)
        def call
          macros = {}

          macros[:has_secure_password] = true if match?(/\bhas_secure_password\b/)
          macros[:encrypts] = extract_symbol_args(/\bencrypts\s+/) if match?(/\bencrypts\s+:/)
          macros[:normalizes] = extract_symbol_args(/\bnormalizes\s+/) if match?(/\bnormalizes\s+:/)
          macros[:has_one_attached] = scan_single_symbol(/\bhas_one_attached\s+:(\w+)/) if match?(/\bhas_one_attached\s+:/)
          macros[:has_many_attached] = scan_single_symbol(/\bhas_many_attached\s+:(\w+)/) if match?(/\bhas_many_attached\s+:/)
          macros[:has_rich_text] = scan_single_symbol(/\bhas_rich_text\s+:(\w+)/) if match?(/\bhas_rich_text\s+:/)
          macros[:broadcasts] = extract_broadcasts if match?(/\bbroadcasts/)
          macros[:generates_token_for] = scan_single_symbol(/\bgenerates_token_for\s+:(\w+)/) if match?(/\bgenerates_token_for\s+:/)
          macros[:serialize] = scan_single_symbol(/\bserialize\s+:(\w+)/) if match?(/\bserialize\s+:/)
          macros[:store] = scan_single_symbol(/\bstore(?:_accessor)?\s+:(\w+)/) if match?(/\bstore(?:_accessor)?\s+:/)
          macros[:delegations] = extract_delegations.presence
          macros[:delegate_missing_to] = extract_delegate_missing_to

          macros.compact.reject { |_, value| value.is_a?(Array) && value.empty? }
        rescue StandardError
          {}
        end

        private

        attr_reader :source

        def match?(pattern)
          source.match?(pattern)
        end

        def extract_symbol_args(prefix_pattern)
          source.scan(/#{prefix_pattern}(.+)/).flat_map { |match| match[0].scan(/:(\w+)/).flatten }
        end

        def scan_single_symbol(pattern)
          source.scan(pattern).flatten
        end

        def extract_broadcasts
          source.scan(/\b(broadcasts_to|broadcasts_refreshes_to|broadcasts)\b/).flatten.uniq
        end

        def extract_delegations
          source.scan(/\bdelegate\s+(.+?),\s*to:\s*:(\w+)/).map do |methods_str, target|
            { methods: methods_str.scan(/:(\w+)/).flatten, to: target }
          end
        end

        def extract_delegate_missing_to
          match = source.match(/\bdelegate_missing_to\s+:(\w+)/)
          match ? match[1] : nil
        end
      end
    end
  end
end

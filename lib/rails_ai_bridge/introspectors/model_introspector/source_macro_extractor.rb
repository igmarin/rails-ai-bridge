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
          build_macros
        rescue StandardError
          # Fails silently as it's an optional metadata source
          {}
        end

        def build_macros
          macros = {}
          populate_macros(macros)
          self.class.filter_empty_arrays(macros)
        end

        def self.filter_empty_arrays(macros)
          macros.compact.reject { |_, value| value.is_a?(Array) && value.empty? }
        end

        def populate_macros(macros)
          add_security_macros(macros)
          add_normalization_macros(macros)
          add_attachment_macros(macros)
          add_action_text_macros(macros)
        end

        def add_action_text_macros(macros)
          add_broadcast_macros(macros)
          add_token_macros(macros)
          add_storage_macros(macros)
        end

        def add_storage_macros(macros)
          add_serialization_macros(macros)
          add_delegation_macros(macros)
        end

        private

        attr_reader :source

        def add_security_macros(macros)
          macros[:has_secure_password] = true if match?(/\bhas_secure_password\b/)
          macros[:encrypts] = extract_symbol_args(/\bencrypts\s+/) if match?(/\bencrypts\s+:/)
        end

        def add_normalization_macros(macros)
          macros[:normalizes] = extract_symbol_args(/\bnormalizes\s+/) if match?(/\bnormalizes\s+:/)
        end

        def add_attachment_macros(macros)
          macros[:has_one_attached] = scan_single_symbol(/\bhas_one_attached\s+:(\w+)/) if match?(/\bhas_one_attached\s+:/)
          macros[:has_many_attached] = scan_single_symbol(/\bhas_many_attached\s+:(\w+)/) if match?(/\bhas_many_attached\s+:/)
          macros[:has_rich_text] = scan_single_symbol(/\bhas_rich_text\s+:(\w+)/) if match?(/\bhas_rich_text\s+:/)
        end

        def add_broadcast_macros(macros)
          macros[:broadcasts] = extract_broadcasts if match?(/\bbroadcasts/)
        end

        def add_token_macros(macros)
          macros[:generates_token_for] = scan_single_symbol(/\bgenerates_token_for\s+:(\w+)/) if match?(/\bgenerates_token_for\s+:/)
        end

        def add_serialization_macros(macros)
          macros[:serialize] = scan_single_symbol(/\bserialize\s+:(\w+)/) if match?(/\bserialize\s+:/)
          macros[:store] = scan_single_symbol(/\bstore(?:_accessor)?\s+:(\w+)/) if match?(/\bstore(?:_accessor)?\s+:/)
        end

        def add_delegation_macros(macros)
          macros[:delegations] = extract_delegations.presence
          macros[:delegate_missing_to] = extract_delegate_missing_to
        end

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

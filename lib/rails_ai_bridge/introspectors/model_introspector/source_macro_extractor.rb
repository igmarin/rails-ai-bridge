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
        PATTERNS = {
          has_secure_password: /\bhas_secure_password\b/,
          encrypts: /\bencrypts\s+:/,
          normalizes: /\bnormalizes\s+:/,
          has_one_attached: /\bhas_one_attached\s+:(\w+)/,
          has_many_attached: /\bhas_many_attached\s+:(\w+)/,
          has_rich_text: /\bhas_rich_text\s+:(\w+)/,
          broadcasts: /\bbroadcasts/,
          generates_token_for: /\bgenerates_token_for\s+:(\w+)/,
          serialize: /\bserialize\s+:(\w+)/,
          store: /\bstore(?:_accessor)?\s+:(\w+)/,
          delegations: /\bdelegate\s+(.+?),\s*to:\s*:(\w+)/,
          delegate_missing_to: /\bdelegate_missing_to\s+:(\w+)/,
          broadcasts_variants: /\b(broadcasts_to|broadcasts_refreshes_to|broadcasts)\b/
        }.freeze

        SYMBOL_ARG_PREFIXES = {
          encrypts: /\bencrypts\s+/,
          normalizes: /\bnormalizes\s+/
        }.freeze

        # @param source [String] the Ruby source code of the model file
        def initialize(source)
          @source = source
        end

        # @return [Hash] detected macros (empty arrays removed)
        def call
          build_macros
        rescue StandardError
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
          add_broadcast_macros(macros)
          add_token_macros(macros)
          add_serialization_macros(macros)
          add_delegation_macros(macros)
        end

        private

        attr_reader :source

        def add_security_macros(macros)
          macros[:has_secure_password] = true if match?(PATTERNS[:has_secure_password])
          macros[:encrypts] = extract_symbol_args(SYMBOL_ARG_PREFIXES[:encrypts]) if match?(PATTERNS[:encrypts])
        end

        def add_normalization_macros(macros)
          macros[:normalizes] = extract_symbol_args(SYMBOL_ARG_PREFIXES[:normalizes]) if match?(PATTERNS[:normalizes])
        end

        def add_attachment_macros(macros)
          add_single_attached(macros)
          add_many_attached(macros)
          add_rich_text(macros)
        end

        def add_single_attached(macros)
          pattern = PATTERNS[:has_one_attached]
          macros[:has_one_attached] = scan_single_symbol(pattern) if match?(pattern)
        end

        def add_many_attached(macros)
          pattern = PATTERNS[:has_many_attached]
          macros[:has_many_attached] = scan_single_symbol(pattern) if match?(pattern)
        end

        def add_rich_text(macros)
          pattern = PATTERNS[:has_rich_text]
          macros[:has_rich_text] = scan_single_symbol(pattern) if match?(pattern)
        end

        def add_broadcast_macros(macros)
          macros[:broadcasts] = extract_broadcasts if match?(PATTERNS[:broadcasts])
        end

        def add_token_macros(macros)
          pattern = PATTERNS[:generates_token_for]
          macros[:generates_token_for] = scan_single_symbol(pattern) if match?(pattern)
        end

        def add_serialization_macros(macros)
          pattern_serialize = PATTERNS[:serialize]
          macros[:serialize] = scan_single_symbol(pattern_serialize) if match?(pattern_serialize)

          pattern_store = PATTERNS[:store]
          macros[:store] = scan_single_symbol(pattern_store) if match?(pattern_store)
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
          source.scan(PATTERNS[:broadcasts_variants]).flatten.uniq
        end

        def extract_delegations
          source.scan(PATTERNS[:delegations]).map do |methods_str, target|
            { methods: methods_str.scan(/:(\w+)/).flatten, to: target }
          end
        end

        def extract_delegate_missing_to
          match = source.match(PATTERNS[:delegate_missing_to])
          match ? match[1] : nil
        end
      end
    end
  end
end

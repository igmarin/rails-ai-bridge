# frozen_string_literal: true

require 'yaml'

module RailsAiBridge
  # Reads and writes which assistant formats +rails ai:bridge+ regenerates by default.
  #
  # The install generator creates {RELATIVE_PATH} with a YAML +formats+ list (a subset of
  # {FORMAT_KEYS}). When the file is missing, invalid, or lists no recognized formats,
  # callers treat the result as +nil+ and fall back to generating all formats.
  #
  # @example install.yml
  #   formats:
  #     - claude
  #     - codex
  #
  # @see RailsAiBridge::Generators::InstallGenerator
  class AssistantFormatsPreference
    # Path of the preference file relative to +Rails.root+.
    RELATIVE_PATH = 'config/rails_ai_bridge/install.yml'

    # All recognized format keys (order is not significant).
    FORMAT_KEYS = %i[claude codex cursor windsurf copilot json gemini].freeze

    class << self
      # Absolute path to the preference file for the current Rails application.
      #
      # @return [Pathname, nil] +nil+ when +Rails.application+ is unavailable
      def config_path
        return nil unless defined?(Rails) && Rails.application

        Rails.root.join(RELATIVE_PATH)
      end

      # Returns the subset of formats requested for the default +rails ai:bridge+ task.
      # Returns +nil+ when the file is absent, invalid, or contains no recognized formats
      # (callers should interpret +nil+ as "generate all formats").
      #
      # @return [Array<Symbol>, nil]
      def formats_for_default_bridge_task
        path = config_path
        return nil unless path&.file?

        data = load_yaml(path)
        return nil unless data.is_a?(Hash)

        raw = data['formats'] || data[:formats]
        return nil if raw.nil?

        fmts = Array(raw).map { |f| f.to_s.downcase.to_sym } & FORMAT_KEYS
        fmts.empty? ? nil : fmts.uniq
      end

      # Writes +install.yml+ with the requested formats filtered against {FORMAT_KEYS}.
      #
      # @param formats [Array<Symbol, String>] desired format keys
      # @raise [RailsAiBridge::Error] when +Rails.application+ is unavailable
      # @return [void]
      def write!(formats:)
        path = config_path
        raise Error, 'Rails app not available' unless path

        path.dirname.mkpath
        list = Array(formats).map { |f| f.to_s.downcase }.uniq & FORMAT_KEYS.map(&:to_s)
        File.write(path.to_s, YAML.dump({ 'formats' => list }))
      end

      private

      # @param path [Pathname]
      # @return [Hash, nil] parsed data or +nil+ on syntax/IO error
      def load_yaml(path)
        YAML.safe_load_file(path, permitted_classes: [Symbol],
                                  permitted_symbols: [],
                                  aliases: true)
      rescue Psych::SyntaxError, Errno::ENOENT
        nil
      end
    end
  end
end

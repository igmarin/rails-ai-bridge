# frozen_string_literal: true

require "yaml"

module RailsAiBridge
  # Reads and writes which assistant formats +rails ai:bridge+ regenerates by default.
  #
  # The install generator creates {RELATIVE_PATH} with a YAML +formats+ list (subset of {FORMAT_KEYS}).
  # When the file is missing or invalid, callers treat that as “all formats”. Omitting +json+ skips +.ai-context.json+
  # unless the user runs +rails ai:bridge:json+ or +rails ai:bridge:all+.
  #
  # @see ContextFileSerializer
  class AssistantFormatsPreference
    # Path relative to +Rails.root+ for the persisted preference file.
    RELATIVE_PATH = "config/rails_ai_bridge/install.yml"

    # Allowed keys for the +formats+ array in YAML (order not significant).
    FORMAT_KEYS = %i[claude codex cursor windsurf copilot json].freeze

    class << self
      # Absolute path to the preference file when a Rails application is loaded.
      #
      # @return [Pathname, nil] +nil+ when +Rails.application+ is not available
      def config_path
        return nil unless defined?(Rails) && Rails.application

        Rails.root.join(RELATIVE_PATH)
      end

      # Normalized format list for the default +rails ai:bridge+ task.
      #
      # @return [Array<Symbol>, nil] subset of {FORMAT_KEYS}, or +nil+ when the file is missing / invalid /
      #   when +formats+ should fall back to “all outputs”
      def formats_for_default_bridge_task
        path = config_path
        return nil unless path&.file?

        data = load_yaml(path)
        return nil if data.nil? || !data.is_a?(Hash)

        raw = data["formats"] || data[:formats]
        return nil if raw.nil?

        fmts = Array(raw).map { |f| f.to_s.downcase.to_sym } & FORMAT_KEYS
        fmts.empty? ? nil : fmts.uniq
      end

      # Writes +install.yml+ with a normalized +formats+ list.
      #
      # @param formats [Array<Symbol, String>] values intersected with {FORMAT_KEYS}
      # @raise [RailsAiBridge::Error] when +Rails.application+ is unavailable (+config_path+ is +nil+)
      # @return [void]
      def write!(formats:)
        path = config_path
        raise Error, "Rails app not available" unless path

        path.dirname.mkpath
        list = Array(formats).map { |f| f.to_s.downcase }.uniq & FORMAT_KEYS.map(&:to_s)
        File.write(path.to_s, YAML.dump({ "formats" => list }))
      end

      private

      # @param path [Pathname]
      # @return [Object, nil] parsed Hash or +nil+ on syntax error / missing file
      def load_yaml(path)
        YAML.safe_load(File.read(path), permitted_classes: [ Symbol ], permitted_symbols: [], aliases: true)
      rescue Psych::SyntaxError, Errno::ENOENT
        nil
      end
    end
  end
end

# frozen_string_literal: true

module RailsAiBridge
  class Watcher
    # Detects fingerprint changes and regenerates context via {RailsAiBridge.generate_context}.
    # Single responsibility: fingerprint state and regeneration (no stderr).
    class BridgeRegenerator
      # @return [String] last computed fingerprint digest
      attr_reader :last_fingerprint

      # @param app [Rails::Application] host application
      def initialize(app)
        @app = app
        @last_fingerprint = Fingerprinter.compute(@app)
      end

      # @return [Boolean] whether the app fingerprint differs from {#last_fingerprint}
      def change_pending?
        Fingerprinter.changed?(@app, @last_fingerprint)
      end

      # Updates the stored fingerprint and runs {RailsAiBridge.generate_context}.
      #
      # @return [Hash] +:written+ and +:skipped+ file path lists
      def regenerate!
        @last_fingerprint = Fingerprinter.compute(@app)
        RailsAiBridge.generate_context(@app, format: :all, split_rules: true)
      end
    end
  end
end

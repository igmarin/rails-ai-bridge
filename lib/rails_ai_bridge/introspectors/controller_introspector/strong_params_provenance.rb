# frozen_string_literal: true

module RailsAiBridge
  module Introspectors
    class ControllerIntrospector
      # Decides how strong-params methods are labelled. Prism confirms a method when its scan
      # finds it as an instance +def+ directly in this controller's class body. The section is
      # +:prism+ only when every method the regex found is confirmed. Otherwise it stays +:regex+,
      # so one unconfirmed method keeps the whole section inferred.
      class StrongParamsProvenance
        # @param scanner [StaticPrismScanner, nil] Prism scanner for this run, or nil when disabled
        # @param path [String, nil] controller source file
        # @param class_name [String, nil] the controller's full class name, such as +Admin::ReportsController+
        def initialize(scanner, path, class_name)
          @scanner = scanner
          @path = path
          @class_name = class_name
        end

        # @param strong_params [Array<String>] method names the source regex found
        # @return [Symbol] +:prism+ when every name is confirmed, otherwise +:regex+
        def call(strong_params)
          confirmed = confirmed_methods
          return :regex unless confirmed

          (strong_params - confirmed).empty? ? :prism : :regex
        end

        private

        # @return [Array<String>, nil] instance methods Prism finds in this controller's body, or nil when the scan fails
        def confirmed_methods
          return unless @scanner && @path

          facts = @scanner.facts_for(@path)[:facts]
          facts&.select { |fact| fact[:kind] == :def && fact[:owner] == @class_name }&.pluck(:name)
        end
      end
    end
  end
end

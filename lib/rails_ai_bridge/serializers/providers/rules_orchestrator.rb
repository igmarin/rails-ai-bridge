# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    module Providers
      # Orchestrates the assembly of the compact project rules document.
      #
      # This class remains a small facade over collaborator builders so the public
      # serializer entrypoint stays stable while section-specific formatting lives
      # in focused objects.
      class RulesOrchestrator < RailsAiBridge::Serializers::Providers::Base
        # @param context [Hash] The introspection context containing application data.
        # @param config [RailsAiBridge::Configuration] The configuration object.
        def initialize(context:, config: RailsAiBridge.configuration)
          super(context: context)
          @config = config
        end

        # @return [String] The generated Markdown content.
        def call
          Collaborators::RulesDocumentBuilder.new(context: context, config: @config).call.join("\n")
        end
      end
    end
  end
end

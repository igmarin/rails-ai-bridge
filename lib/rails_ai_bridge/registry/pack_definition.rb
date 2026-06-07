# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Immutable value object describing a single pack's source and loading behaviour.
    #
    # @!attribute [r] source
    #   @return [String] GitHub source identifier, e.g. "igmarin/ruby-core-skills"
    # @!attribute [r] tile
    #   @return [String] relative path to the pack's tile manifest, usually "tile.json"
    # @!attribute [r] always_loaded
    #   @return [Boolean] whether this pack is unconditionally loaded
    # @!attribute [r] depends_on
    #   @return [Array<String>] names of packs this pack depends on
    PackDefinition = Data.define(:source, :tile, :always_loaded, :depends_on) do
      # @return [Boolean]
      def always_loaded? = always_loaded
    end
  end
end

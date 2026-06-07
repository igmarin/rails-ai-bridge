# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Immutable value object describing a single pack's source and loading behaviour.
    #
    # @!attribute [r] source
    #   @return [String] pack source — local path, full git URL, or "owner/repo" shorthand
    # @!attribute [r] tile
    #   @return [String] relative path to the pack's tile manifest, usually "directory.json"
    # @!attribute [r] always_loaded
    #   @return [Boolean] whether this pack is unconditionally loaded
    # @!attribute [r] depends_on
    #   @return [Array<String>] names of packs this pack depends on
    # @!attribute [r] ref
    #   @return [String, nil] optional git ref (branch, tag, or SHA) to pin the pack version;
    #     nil means use the default branch (HEAD)
    PackDefinition = Data.define(:source, :tile, :always_loaded, :depends_on, :ref) do
      # @return [Boolean]
      def always_loaded? = always_loaded
    end
  end
end

# frozen_string_literal: true

require 'json'
require 'yaml'

module RailsAiBridge
  # Registry resolution system for skill packs.
  #
  # Provides priority-based loading of skill packs from git repositories,
  # deprecation redirect handling, and framework auto-detection.
  #
  # @see Registry::RegistryManifest
  # @see Registry::TileManifest
  # @see Registry::FrontmatterParser
  module Registry
  end
end

require_relative 'registry/manifest'
require_relative 'registry/tile_manifest'
require_relative 'registry/frontmatter_parser'

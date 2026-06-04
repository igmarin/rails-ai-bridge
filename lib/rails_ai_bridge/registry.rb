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
  # @see Registry::PackDefinition
  # @see Registry::TileManifest
  # @see Registry::FrontmatterParser
  # @see Registry::PackDetector
  # @see Registry::GitRunner
  # @see Registry::DefaultGitRunner
  # @see Registry::SkillSourceResolver
  # @see Registry::PackResolver
  # @see Registry::Resolver
  # @see Registry::LoadedPack
  # @see Registry::ResolvedSkill
  # @see Registry::SkillSummary
  module Registry
  end
end

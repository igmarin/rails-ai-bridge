# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Verifies the registry manifest is present, valid, and resolvable.
      #
      # Checks (in order):
      # 1. The configured +registry_manifest_path+ exists.
      # 2. The manifest JSON parses successfully.
      # 3. +RegistryManifest.validate!+ passes schema validation.
      # 4. +Registry.build_resolver+ returns a non-nil resolver.
      # 5. The lockfile exists and matches (when +lockfile_path+ is configured).
      #
      # Each failure short-circuits with an actionable fix hint so the user can
      # resolve the first problem before chasing downstream symptoms.
      class RegistryChecker < BaseChecker
        # @return [Doctor::Check] +:pass+, +:warn+, or +:fail+
        def call
          return missing_manifest_check unless manifest_path_exists?

          return invalid_json_check unless manifest_parses?

          return validation_failed_check unless manifest_validates?

          resolver = build_resolver
          return resolver_failed_check(resolver) unless resolver

          return lockfile_check if lockfile_configured? && !lockfile_exists?

          new_check(name: 'Registry', status: :pass, message: 'Registry manifest is valid and resolvable', fix: nil)
        end

        private

        def registry_config
          RailsAiBridge.configuration.registry
        end

        def manifest_path
          registry_config.registry_manifest_path
        end

        def manifest_path_exists?
          File.exist?(manifest_path)
        end

        def missing_manifest_check
          new_check(
            name: 'Registry',
            status: :warn,
            message: "Registry manifest not found at `#{manifest_path}`",
            fix: 'Create a registry manifest file — see docs/skill-registry-guide.md'
          )
        end

        def manifest_parses?
          parsed_manifest
          true
        rescue ArgumentError
          false
        end

        def invalid_json_check
          new_check(
            name: 'Registry',
            status: :fail,
            message: "Registry manifest at `#{manifest_path}` contains invalid JSON or could not be read",
            fix: "Fix the JSON syntax in the manifest file — run `ruby -rjson -e 'JSON.parse(File.read(ARGV[0]))' #{manifest_path}` to see the parse error"
          )
        end

        def parsed_manifest
          @parsed_manifest ||= RailsAiBridge::Registry::RegistryManifest.from_file(manifest_path)
        end

        def manifest_validates?
          RailsAiBridge::Registry::RegistryManifest.validate!(raw_manifest_hash)
          true
        rescue RailsAiBridge::Registry::RegistryManifest::ValidationError
          false
        end

        def raw_manifest_hash
          JSON.parse(File.read(manifest_path))
        end

        def validation_failed_check
          new_check(
            name: 'Registry',
            status: :fail,
            message: "Registry manifest at `#{manifest_path}` failed schema validation",
            fix: 'Check the manifest structure — see docs/skill-registry-guide.md for the expected schema'
          )
        end

        def build_resolver
          RailsAiBridge::Registry.build_resolver(registry_config)
        end

        def resolver_failed_check(resolver)
          new_check(
            name: 'Registry',
            status: :warn,
            message: "Registry manifest parsed but resolver returned nil#{resolver_reason(resolver)}",
            fix: 'Check that all pack sources are reachable and git is available — see logs for details'
          )
        end

        def resolver_reason(resolver)
          return '' unless resolver.nil?

          ' (manifest missing or pack sources could not be resolved)'
        end

        def lockfile_configured?
          registry_config.lockfile_path
        end

        def lockfile_exists?
          File.exist?(registry_config.lockfile_path)
        end

        def lockfile_check
          new_check(
            name: 'Registry',
            status: :warn,
            message: "Lockfile not found at `#{registry_config.lockfile_path}`",
            fix: 'Run `rails ai:registry:lock` to generate the lockfile, or set lockfile_path to nil to disable verification'
          )
        end
      end
    end
  end
end

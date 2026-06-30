# frozen_string_literal: true

require 'json'
require 'fileutils'

module RailsAiBridge
  module Registry
    # Records and verifies expected git commit SHAs for skill packs.
    #
    # The lockfile is a JSON document keyed by pack name. Each entry stores the
    # pack source, ref, and the resolved commit SHA. When verification is enabled,
    # {PackResolver} compares the locked SHA against the actual HEAD of the cloned
    # repository and fails closed on mismatch.
    class Lockfile
      # Represents one lockfile entry.
      Entry = Data.define(:pack_name, :source, :ref, :commit_sha)

      class << self
        # Loads a lockfile from disk.
        #
        # @param path [String, nil] path to the lockfile; nil means no lockfile
        # @return [Lockfile] empty lockfile when path is nil or the file does not exist
        def load(path)
          return new({}) if path.nil? || !File.exist?(path)

          raw = File.read(path)
          data = JSON.parse(raw)
          entries = data.transform_values do |entry|
            Entry.new(
              pack_name: entry['pack_name'],
              source: entry['source'],
              ref: entry['ref'],
              commit_sha: entry['commit_sha']
            )
          end
          new(entries)
        rescue JSON::ParserError => error
          raise ArgumentError, "Invalid lockfile JSON at #{path}: #{error.message}"
        end

        # Generates lockfile entries by resolving every pack in the manifest.
        #
        # @param manifest [RegistryManifest]
        # @param source_resolver [SkillSourceResolver]
        # @return [Hash{String => Entry}]
        def generate(manifest, source_resolver)
          manifest.packs.each_with_object({}) do |(name, pack_def), entries|
            base_path = source_resolver.resolve(pack_def.source, ref: pack_def.ref)
            commit_sha = source_resolver.current_commit(base_path)
            entries[name] = Entry.new(
              pack_name: name,
              source: pack_def.source,
              ref: pack_def.ref,
              commit_sha: commit_sha
            )
          end
        end

        # Writes a lockfile to disk for the given manifest.
        #
        # @param path [String]
        # @param manifest [RegistryManifest]
        # @param source_resolver [SkillSourceResolver]
        # @return [void]
        def write(path, manifest, source_resolver)
          entries = generate(manifest, source_resolver)
          new(entries).write(path)
        end
      end

      # @param entries [Hash{String => Entry}] map of pack name to lockfile entry
      def initialize(entries)
        @entries = entries.freeze
      end

      delegate :any?, to: :@entries

      # @param pack_name [String]
      # @return [Entry, nil]
      def entry(pack_name)
        @entries[pack_name]
      end

      # Serializes the lockfile to JSON.
      #
      # @return [String]
      def to_json(*)
        data = @entries.transform_values do |entry|
          {
            'pack_name' => entry.pack_name,
            'source' => entry.source,
            'ref' => entry.ref,
            'commit_sha' => entry.commit_sha
          }
        end
        JSON.pretty_generate(data)
      end

      # Writes the lockfile to disk.
      #
      # @param path [String]
      # @return [void]
      def write(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "#{to_json}\n")
      end
    end
  end
end

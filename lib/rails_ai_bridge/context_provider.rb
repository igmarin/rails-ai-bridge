# frozen_string_literal: true

module RailsAiBridge
  # Builds and caches introspection snapshots for MCP tools and resources.
  # This keeps all runtime reads aligned behind one explicit boundary.
  class ContextProvider
    @cache = Hash.new { |hash, key| hash[key] = { sections: {} } }
    @mutex = Mutex.new

    class << self
      # Returns the latest introspection snapshot for the given app, reusing a
      # cached value while the TTL is valid and the fingerprint is unchanged.
      #
      # @param app [Rails::Application] application to introspect
      # @return [Hash] introspection payload
      def fetch(app = Rails.application)
        mutex.synchronize do
          cached = cache[cache_key(app)]
          return rebuild(app) unless cached[:full]

          current_fingerprint = Fingerprinter.snapshot(app)
          return cached[:full][:context] if ttl_valid?(cached[:full]) && current_fingerprint == cached[:full][:fingerprint]

          rebuild(app, fingerprint: current_fingerprint)
        end
      end

      # Returns a single introspection section using a dedicated cache entry for
      # that section. If a valid full snapshot is already cached, reuse it.
      #
      # @param section [Symbol] introspector key to retrieve
      # @param app [Rails::Application] application to introspect
      # @return [Object, nil] requested section payload
      def fetch_section(section, app = Rails.application)
        mutex.synchronize do
          key = cache_key(app)
          cached = cache[key]
          current_fingerprint = Fingerprinter.snapshot(app)

          full = cached[:full]
          return full[:context][section] if full && ttl_valid?(full) && current_fingerprint == full[:fingerprint]

          section_entry = cached[:sections][section]
          return section_entry[:context] if section_entry && ttl_valid?(section_entry) && current_fingerprint == section_entry[:fingerprint]

          rebuild_section(section, app, fingerprint: current_fingerprint)
        end
      end

      # Clears all cached snapshots.
      #
      # @return [void]
      def reset!
        @cache = build_cache_store
        @mutex = Mutex.new
      end

      private

      attr_reader :cache, :mutex

      # Builds the default cache structure for full snapshots and per-section entries.
      #
      # @return [Hash]
      def build_cache_store
        Hash.new { |hash, key| hash[key] = { sections: {} } }
      end

      def rebuild(app, fingerprint: nil)
        context = RailsAiBridge.introspect(app)
        key = cache_key(app)
        cache[key][:full] = {
          context: context,
          fingerprint: fingerprint || Fingerprinter.snapshot(app),
          fetched_at: monotonic_now
        }
        context.each do |section_name, section_value|
          next unless section_name.is_a?(Symbol)
          next if metadata_key?(section_name)

          cache[key][:sections][section_name] = {
            context: section_value,
            fingerprint: cache[key][:full][:fingerprint],
            fetched_at: cache[key][:full][:fetched_at]
          }
        end
        context
      end

      def rebuild_section(section, app, fingerprint:)
        context = RailsAiBridge.introspect(app, only: [section])
        cache[cache_key(app)][:sections][section] = {
          context: context[section],
          fingerprint: fingerprint,
          fetched_at: monotonic_now
        }
        context[section]
      end

      def ttl_valid?(cached)
        (monotonic_now - cached[:fetched_at]) < RailsAiBridge.configuration.cache_ttl
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def cache_key(app)
        app.object_id
      end

      def metadata_key?(section_name)
        %i[app_name ruby_version rails_version environment generated_at generator].include?(section_name)
      end
    end
  end
end

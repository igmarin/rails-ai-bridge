# frozen_string_literal: true

require 'json'

module RailsAiBridge
  # Utility module to embed and extract freshness metadata from generated bridge files.
  module FreshnessHeader
    HEADER_PATTERN = /\A<!-- Generated at: ([^|]+) \| Source fingerprint: ([a-f0-9]{12})(?: \| rails-ai-bridge: v([^ ]+))? -->/i

    class << self
      # Embeds the freshness header appropriate for the given format.
      # For JSON, merges a _meta key; for Markdown, prepends an HTML comment.
      #
      # @param fmt [Symbol] format key (e.g. :json, :claude)
      # @param content [String] raw serialized content
      # @param timestamp [String] ISO 8601 UTC timestamp
      # @param fingerprint [String] 12-char SHA256 hex fingerprint
      # @return [String] content with embedded freshness metadata
      def embed_for(fmt, content, timestamp, fingerprint)
        return embed_json(content, timestamp, fingerprint) if fmt == :json

        embed(content, timestamp, fingerprint)
      end

      # Extracts [fingerprint, timestamp] tuple from content, dispatching on format.
      #
      # @param fmt [Symbol] format key (e.g. :json, :claude)
      # @param content [String, nil] file content to inspect
      # @return [Array(String, String), Array(nil, nil)]
      def extract_metadata_for(fmt, content)
        return [nil, nil] unless content
        return extract_json_metadata(content) if fmt == :json

        [extract_fingerprint(content), extract_timestamp(content)]
      end

      # Extracts the fingerprint from content, dispatching on format.
      # Handles both JSON (_meta key) and Markdown (HTML comment header) formats.
      #
      # @param fmt [Symbol] format key (e.g. :json, :claude)
      # @param content [String] file content to inspect
      # @return [String, nil] fingerprint if found, nil otherwise
      def extract_fingerprint_for(fmt, content)
        return extract_json_fingerprint(content) if fmt == :json

        extract_fingerprint(content)
      end

      # Embeds the freshness header at the top of the content (Markdown formats).
      #
      # @param content [String]
      # @param timestamp [String] ISO 8601 UTC timestamp
      # @param fingerprint [String] 12-char SHA256 hex fingerprint
      # @return [String] content prefixed with freshness header
      def embed(content, timestamp, fingerprint)
        header = "<!-- Generated at: #{timestamp} | Source fingerprint: #{fingerprint} | rails-ai-bridge: v#{RailsAiBridge::VERSION} -->\n"
        header + content
      end

      # Extracts the fingerprint from the markdown freshness header.
      #
      # @param content [String]
      # @return [String, nil] fingerprint if found, nil otherwise
      def extract_fingerprint(content)
        match = content.match(HEADER_PATTERN)
        match ? match[2] : nil
      end

      # Extracts the timestamp from the markdown freshness header.
      #
      # @param content [String]
      # @return [String, nil] timestamp if found, nil otherwise
      def extract_timestamp(content)
        match = content.match(HEADER_PATTERN)
        match ? match[1] : nil
      end

      # Extracts the gem version from the markdown freshness header.
      #
      # @param content [String]
      # @return [String, nil] gem version if found, nil otherwise
      def extract_version(content)
        match = content.match(HEADER_PATTERN)
        match ? match[3] : nil
      end

      private

      # Embeds freshness metadata into JSON content via a +_meta+ key.
      # The freshness fields always take precedence over any existing +_meta+ in the content.
      #
      # @param content [String] raw JSON string
      # @param timestamp [String] ISO 8601 UTC timestamp
      # @param fingerprint [String] 12-char SHA256 hex fingerprint
      # @return [String] pretty-printed JSON with embedded freshness metadata
      def embed_json(content, timestamp, fingerprint)
        parsed = JSON.parse(content)
        JSON.pretty_generate(parsed.merge(
                               '_meta' => {
                                 'generated_at' => timestamp,
                                 'source_fingerprint' => fingerprint,
                                 'gem_version' => RailsAiBridge::VERSION
                               }
                             ))
      rescue JSON::ParserError
        content
      end

      # Extracts the source fingerprint from JSON content's +_meta+ key.
      #
      # @param content [String] JSON string
      # @return [String, nil] fingerprint if found, nil otherwise
      def extract_json_fingerprint(content)
        parsed = JSON.parse(content)
        parsed.dig('_meta', 'source_fingerprint')
      rescue StandardError
        nil
      end

      # Extracts both fingerprint and timestamp from JSON content's +_meta+ key.
      #
      # @param content [String] JSON string
      # @return [Array(String, String), Array(nil, nil)] [fingerprint, timestamp] tuple
      def extract_json_metadata(content)
        parsed = JSON.parse(content)
        [parsed.dig('_meta', 'source_fingerprint'), parsed.dig('_meta', 'generated_at')]
      rescue JSON::ParserError
        [nil, nil]
      end
    end
  end
end

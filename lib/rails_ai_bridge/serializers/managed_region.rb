# frozen_string_literal: true

module RailsAiBridge
  module Serializers
    # Delimits the gem-owned portion of a generated provider file so hand-authored
    # content around it survives regeneration.
    #
    # A managed file looks like:
    #
    #   House rules the team wrote by hand.
    #
    #   <!-- BEGIN rails-ai-bridge: generated. Edits inside this block are overwritten on `rails ai:bridge`. -->
    #   …generated context…
    #   <!-- END rails-ai-bridge -->
    #
    # Only the first region is treated as managed; everything else in the file belongs
    # to the user and is never rewritten. An unterminated BEGIN marker (a truncated or
    # hand-edited file) is treated as running to end of file, so the next run heals it
    # rather than nesting a second block inside the first.
    module ManagedRegion
      BEGIN_MARKER = '<!-- BEGIN rails-ai-bridge: generated. Edits inside this block are overwritten on `rails ai:bridge`. -->'
      END_MARKER   = '<!-- END rails-ai-bridge -->'

      # Tolerant of marker-text drift (older gem versions worded the notice differently)
      # and of trailing whitespace, so a region written by any version is still recognised.
      BEGIN_PATTERN  = /^<!-- BEGIN rails-ai-bridge:[^\n]*-->[^\S\n]*\n/
      END_PATTERN    = /^<!-- END rails-ai-bridge -->[^\S\n]*(?:\n|\z)/
      REGION_PATTERN = /#{BEGIN_PATTERN}(.*?)(?:#{END_PATTERN}|\z)/m

      class << self
        # Wraps generated content in the managed-region markers.
        #
        # @param payload [String] generated content
        # @return [String] marked block, newline-terminated
        def wrap(payload)
          "#{BEGIN_MARKER}\n#{payload.to_s.chomp}\n#{END_MARKER}\n"
        end

        # @param content [String, nil] file content to inspect
        # @return [Boolean] +true+ when a managed region is present
        def markers?(content)
          return false unless content

          REGION_PATTERN.match?(content)
        end

        # Extracts the generated payload from a managed file.
        #
        # @param content [String, nil] file content to inspect
        # @return [String, nil] payload without markers, or +nil+ when unmarked
        def extract(content)
          return nil unless content

          content[REGION_PATTERN, 1]&.chomp
        end

        # Returns the gem-owned portion of a file: the managed region when one is
        # present, otherwise the whole file. Lets callers that only care about the
        # generated payload (freshness metadata, staleness checks) stay agnostic
        # about whether managed regions are enabled.
        #
        # @param content [String, nil] file content to inspect
        # @return [String, nil]
        def generated_payload(content)
          extract(content) || content
        end

        # Combines existing file content with a freshly generated payload.
        #
        # * no existing content → the marked block alone
        # * existing content with markers → only the region is replaced
        # * existing content without markers → the block is appended, preserving the file
        #
        # @param existing [String, nil] current file content
        # @param payload [String] generated content
        # @return [String] content to write
        def merge(existing, payload)
          block = wrap(payload)
          return block if existing.nil? || existing.strip.empty?
          # Block form: a String replacement would interpret backslash escapes in the payload.
          return existing.sub(REGION_PATTERN) { block } if markers?(existing)

          "#{existing.rstrip}\n\n#{block}"
        end
      end
    end
  end
end

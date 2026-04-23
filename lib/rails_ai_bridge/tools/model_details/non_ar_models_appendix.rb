# frozen_string_literal: true

module RailsAiBridge
  module Tools
    module ModelDetails
      # Shared Markdown helpers for appending non-ActiveRecord +app/models+ classes to
      # {Tools::GetModelDetails} output and Claude rules files.
      module NonArModelsAppendix
        module_function

        # Fallback tag when a row omits +:tag+.
        DEFAULT_TAG = 'POJO/Service'

        # Human-readable subsection title embedded in the generated Markdown heading.
        SECTION_TITLE = 'POJO/Service under app/models'

        # Normalizes the +:non_ar_models+ introspector payload into an array of row hashes.
        #
        # @param section [Hash, nil] payload from {Introspectors::NonArModelsIntrospector#call}, or +nil+
        # @option section [Array<Hash>] :non_ar_models rows (String or Symbol keys allowed per row)
        # @option section [Array<Hash>] "non_ar_models" same as +:non_ar_models+ when the hash uses string keys (e.g. JSON)
        # @option section [String] :error when introspection failed; treated as empty list
        # @option section [String] "error" same as +:error+ for string-keyed hashes
        # @return [Array<Hash>] rows for {append_markdown}; each row may include +:name+, +:relative_path+, +:tag+
        def entries_from(section)
          return [] unless section.is_a?(Hash)
          return [] if section[:error].present? || section['error'].present?

          Array(section[:non_ar_models] || section['non_ar_models'])
        end

        # Appends a "## Non-ActiveRecord classes (...)" Markdown block when rows exist.
        #
        # @param section [Hash, nil] same shape as for {.entries_from}
        # @return [String] Markdown suffix (empty when there are no rows)
        def append_markdown(section)
          rows = entries_from(section)
          return '' if rows.empty?

          lines = ['', "## Non-ActiveRecord classes (#{SECTION_TITLE})", '']
          rows.each do |row|
            name = row[:name] || row['name']
            path = row[:relative_path] || row['relative_path']
            tag = row[:tag] || row['tag'] || DEFAULT_TAG
            lines << "- **[#{tag}]** `#{name}` — `#{path}`"
          end
          lines << ''
          lines.join("\n")
        end
      end
    end
  end
end

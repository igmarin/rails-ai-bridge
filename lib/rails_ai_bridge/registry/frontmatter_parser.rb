# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Internal utility for extracting YAML frontmatter from skill markdown files.
    #
    # Used by the resolver when a {SkillEntry} carries no +description+ in +tile.json+
    # and a richer description must be sourced from the file itself.
    #
    # @example
    #   metadata = FrontmatterParser.parse(File.read('skills/code_review.md'))
    #   metadata.description #=> "Review Ruby code for correctness and style."
    class FrontmatterParser
      # Raised when frontmatter cannot be parsed from the provided content.
      class ParseError < StandardError; end

      # Immutable value object holding the extracted skill metadata.
      #
      # @!attribute [r] name
      #   @return [String]
      # @!attribute [r] version
      #   @return [String]
      # @!attribute [r] description
      #   @return [String]
      SkillMetadata = Data.define(:name, :version, :description)

      # Parses YAML frontmatter from markdown content.
      #
      # @param content [String] full markdown file content
      # @return [SkillMetadata]
      # @raise [ParseError] if delimiters are missing or required fields are absent
      def self.parse(content)
        lines = extract_frontmatter_lines(content)
        data  = parse_yaml(lines)
        validate_fields!(data)
        SkillMetadata.new(name: data['name'], version: data['version'], description: data['description'])
      end

      # @api private
      def self.extract_frontmatter_lines(content)
        trimmed = content.lstrip
        raise ParseError, 'Missing frontmatter opening delimiter "---"' unless trimmed.start_with?('---')

        lines     = []
        found_end = false

        trimmed[3..].each_line do |line|
          if line.chomp == '---'
            found_end = true
            break
          end
          lines << line
        end

        raise ParseError, 'Missing frontmatter closing delimiter "---" on its own line' unless found_end

        lines
      end

      # @api private
      def self.parse_yaml(lines)
        YAML.safe_load(lines.join, permitted_classes: []) || {}
      end

      # @api private
      def self.validate_fields!(data)
        %w[name version description].each do |field|
          raise ParseError, "Missing required frontmatter field: #{field}" unless data.key?(field)
        end
      end

      private_class_method :extract_frontmatter_lines, :parse_yaml, :validate_fields!
    end
  end
end

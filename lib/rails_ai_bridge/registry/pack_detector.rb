# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Enum-like value object representing detected Ruby frameworks.
    #
    # Used by {PackDetector} to indicate which frameworks are present in a project's Gemfile.
    #
    # @example
    #   frameworks = PackDetector.detect_from_content("gem 'rails'")
    #   frameworks.first #=> DetectedFramework::Rails
    class DetectedFramework
      # Ruby on Rails framework.
      Rails = new
      # Hanami framework.
      Hanami = new
    end

    # Utility for detecting Ruby frameworks in a project's Gemfile.
    #
    # Parses Gemfile content to identify the presence of Rails or Hanami gems,
    # supporting both single and double quotes, with or without version constraints.
    #
    # @example
    #   PackDetector.detect #=> [DetectedFramework::Rails]
    #   PackDetector.detect_in_path('/path/to/project') #=> [DetectedFramework::Hanami]
    #   PackDetector.detect_from_content("gem 'rails'") #=> [DetectedFramework::Rails]
    class PackDetector
      # Detects frameworks by checking the Gemfile in the current working directory.
      #
      # @return [Array<DetectedFramework>] array of detected frameworks
      def self.detect
        detect_in_path('.')
      end

      # Detects frameworks by checking the Gemfile in a given base directory path.
      #
      # @param base_path [String] path to the directory containing a Gemfile
      # @return [Array<DetectedFramework>] array of detected frameworks
      def self.detect_in_path(base_path)
        gemfile_path = File.join(base_path, 'Gemfile')
        if File.exist?(gemfile_path)
          content = File.read(gemfile_path)
          detect_from_content(content)
        else
          []
        end
      end

      # Pure function that parses Gemfile file contents to detect frameworks.
      #
      # Ignores commented lines (starting with #) and matches gem declarations
      # for 'rails' or 'hanami' with various quote styles and optional commas.
      #
      # @param content [String] Gemfile content as a string
      # @return [Array<DetectedFramework>] array of detected frameworks
      # :reek:TooManyStatements -- Necessary complexity for Gemfile parsing with two framework detectors
      def self.detect_from_content(content)
        detected = []
        rails_found = false
        hanami_found = false

        content.each_line do |line|
          trimmed = line.strip
          next if trimmed.start_with?('#')

          rails_found = detect_rails(trimmed, detected, rails_found)
          hanami_found = detect_hanami(trimmed, detected, hanami_found)
        end

        detected
      end

      # @api private
      def self.detect_rails(line, detected, already_found)
        return already_found if already_found

        if line.match?(/gem\s+['"]rails['"]/)
          detected << DetectedFramework::Rails
          true
        else
          false
        end
      end

      # @api private
      def self.detect_hanami(line, detected, already_found)
        return already_found if already_found

        if line.match?(/gem\s+['"]hanami['"]/)
          detected << DetectedFramework::Hanami
          true
        else
          false
        end
      end

      private_class_method :detect_rails, :detect_hanami
    end
  end
end

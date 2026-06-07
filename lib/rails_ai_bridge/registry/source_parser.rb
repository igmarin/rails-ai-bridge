# frozen_string_literal: true

module RailsAiBridge
  module Registry
    # Parses a raw pack source string and returns a typed {ParsedSource} value object.
    #
    # Single responsibility: classify a source string into one of three formats and
    # produce the canonical URL needed to resolve it. Raises {SkillSourceResolver::ResolutionError}
    # for unrecognized formats so callers get a clear error message naming all valid forms.
    #
    # Supported formats:
    #
    # * **Local path** — starts with +/+, +./+, or +../+. Returned as-is; no git needed.
    # * **Full git URL** — starts with +https://+ or +git@+. Used directly as the clone URL.
    # * **GitHub shorthand** — exactly +owner/repo+. Expanded to +https://github.com/owner/repo.git+.
    #
    # @example Local absolute path
    #   SourceParser.parse('/my/skills') #=> #<ParsedSource type=:local_path resolved_url="/my/skills">
    # @example Full URL
    #   SourceParser.parse('https://github.com/org/repo.git') #=> #<ParsedSource type=:git_url ...>
    # @example GitHub shorthand
    #   SourceParser.parse('igmarin/ruby-core-skills') #=> #<ParsedSource type=:github_shorthand ...>
    module SourceParser
      # Immutable value object produced by {SourceParser.parse}.
      #
      # @!attribute [r] type
      #   @return [Symbol] +:local_path+, +:git_url+, or +:github_shorthand+
      # @!attribute [r] resolved_url
      #   @return [String] canonical URL/path suitable for git clone or direct use
      ParsedSource = Data.define(:type, :resolved_url)

      INVALID_SOURCE_MESSAGE = <<~MSG
        Invalid source format: %<source>s

        Valid formats:
          Local path    /absolute/path  OR  ./relative  OR  ../relative
          HTTPS/SSH URL https://github.com/owner/repo.git  OR  git@github.com:owner/repo.git
          GitHub short  owner/repo  (expanded to https://github.com/owner/repo.git)
      MSG

      # @param source [String] raw source string from the registry manifest
      # @return [ParsedSource]
      # @raise [SkillSourceResolver::ResolutionError] for unrecognized formats
      def self.parse(source)
        return parse_local(source)     if local_path?(source)
        return parse_git_url(source)   if git_url?(source)
        return parse_shorthand(source) if github_shorthand?(source)

        raise SkillSourceResolver::ResolutionError, format(INVALID_SOURCE_MESSAGE, source: source)
      end

      # @api private
      def self.local_path?(source)
        source.start_with?('/', './', '../')
      end
      private_class_method :local_path?

      # @api private
      def self.git_url?(source)
        source.start_with?('https://', 'http://', 'git@')
      end
      private_class_method :git_url?

      # @api private
      def self.github_shorthand?(source)
        # Exactly one slash, both segments non-empty, no extra path components
        source.match?(%r{\A[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+\z})
      end
      private_class_method :github_shorthand?

      # @api private
      def self.parse_local(source)
        ParsedSource.new(type: :local_path, resolved_url: source)
      end
      private_class_method :parse_local

      # @api private
      def self.parse_git_url(source)
        ParsedSource.new(type: :git_url, resolved_url: source)
      end
      private_class_method :parse_git_url

      # @api private
      def self.parse_shorthand(source)
        expanded = "https://github.com/#{source}.git"
        ParsedSource.new(type: :github_shorthand, resolved_url: expanded)
      end
      private_class_method :parse_shorthand
    end
  end
end

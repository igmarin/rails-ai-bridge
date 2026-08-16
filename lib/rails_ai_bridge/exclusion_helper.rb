# frozen_string_literal: true

module RailsAiBridge
  # Table name matching for +config.excluded_tables+ (exact names or +*+ globs).
  module ExclusionHelper
    module_function

    # Returns +true+ when +table_name+ matches +pattern+ exactly or via +*+ glob.
    # Table names in Rails are always lowercase snake_case, so matching is case-sensitive.
    #
    # @param pattern [String] exact name (e.g. +"secrets"+) or glob (e.g. +"audit_*"+)
    # @param table_name [String] lowercase table name to test
    # @return [Boolean]
    def table_pattern_match?(pattern, table_name)
      return false if pattern.to_s.empty? || table_name.to_s.empty?

      pat = pattern.to_s
      return pat == table_name unless pat.include?('*')

      File.fnmatch(pat, table_name, File::FNM_EXTGLOB)
    end

    # Returns +true+ when +name+ is an excluded model or maps to an excluded table.
    # Accepts rubydex-decorated tokens such as +PatientRecord::<PatientRecord>+.
    # Demodulized bases match only when the module prefix is the same
    # (+User+ vs +UsersController+, not +User+ vs +Admin::User+).
    #
    # @param name [String, nil] class, association, controller, or route token
    # @param config [#excluded_models, #excluded_table?]
    # @return [Boolean]
    def excluded_class_or_table?(name, config)
      token = normalize_class_token(name)
      return false if token.empty?

      if config.respond_to?(:excluded_models)
        models = Array(config.excluded_models).map(&:to_s)
        return true if models.any? { |excluded| token == excluded || token.start_with?("#{excluded}::") }
        return true if models.any? { |excluded| namespaced_base_match?(token, excluded) }
      end

      return false unless config.respond_to?(:excluded_table?)

      class_stems(token).any? { |stem| config.excluded_table?(stem) }
    end

    # Strips rubydex decoration (+Class::<Class>+) from a related-model token
    # and normalizes route-style +admin/users+ paths to +admin::users+.
    #
    # @param name [String, nil]
    # @return [String]
    def normalize_class_token(name)
      name.to_s.sub(/::<[^>]*>\z/, '').gsub('/', '::')
    end

    # True when demodulized bases match and both tokens share a module prefix.
    #
    # @param token [String]
    # @param excluded [String]
    # @return [Boolean]
    def namespaced_base_match?(token, excluded)
      return false unless module_prefix(token).casecmp?(module_prefix(excluded))

      classify_base(token) == classify_base(excluded)
    end

    # @param name [String]
    # @return [String]
    def module_prefix(name)
      name.to_s.deconstantize
    end

    # @param name [String]
    # @return [String]
    def classify_base(name)
      name.to_s.demodulize.sub(/Controller\z/, '').singularize.camelize
    end

    # Table-name candidates for a class or route/controller token.
    #
    # @param token [String]
    # @return [Array<String>]
    def class_stems(token)
      pieces = [token, token.split('::').last].compact
      pieces << pieces.last.to_s.sub(/Controller\z/, '')
      pieces.flat_map do |piece|
        next [] if piece.empty?

        snake = piece.underscore
        [snake, snake.pluralize, snake.singularize]
      end.uniq
    end
  end
end

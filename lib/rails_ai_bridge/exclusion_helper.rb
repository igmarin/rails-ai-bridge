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
  end
end

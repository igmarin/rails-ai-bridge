# frozen_string_literal: true

module RailsAiBridge
  # Table name matching for +config.excluded_tables+ (exact names or +*+ globs).
  module ExclusionHelper
    module_function

    # @param pattern [String] e.g. +"users"+ or +"audit_*"+
    # @param table_name [String]
    # @return [Boolean]
    def table_pattern_match?(pattern, table_name)
      return false if pattern.to_s.empty? || table_name.to_s.empty?

      p = pattern.to_s
      return p == table_name unless p.include?("*")

      File.fnmatch(p, table_name, File::FNM_EXTGLOB | File::FNM_CASEFOLD)
    end
  end
end

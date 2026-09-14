# frozen_string_literal: true

module RailsAiBridge
  module Tools
    class Query
      # Rejects any SQL that is not a single, non-mutating SELECT statement.
      #
      # v1 deliberately rejects WITH (CTE) queries: mutating CTEs (wCTEs) allow
      # INSERT/UPDATE/DELETE inside a WITH clause, and catching every dialect's
      # wCTE grammar is error-prone. A plain SELECT-only allowlist is the safer
      # starting point; CTE support can be added later behind stricter parsing.
      class Guard
        # Ordered rejection rules: the first matching pattern rejects the
        # statement. One trailing semicolon is tolerated; any inner semicolon
        # is not (a semicolon inside a string literal is rejected too — v1 is
        # conservative because parsing SQL literals is error-prone).
        #
        # The statement must start with SELECT (leading whitespace only). Comments,
        # EXPLAIN, SHOW, VALUES, WITH, and other verbs are rejected — a denylist
        # of mutating keywords is not enough.
        REJECTION_RULES = [
          [/\A\s*\z/, 'SQL must not be empty'],
          [/;\s*\S/, 'only a single statement is allowed (no semicolons)'],
          [/\A\s*with\b/i, 'WITH (CTE) queries are not allowed; rewrite as a plain SELECT'],
          [/\A(?!\s*select\b)/i, 'only SELECT statements are allowed'],
          [/\bfor\s+(update|share|no\s+key\s+update|key\s+share)\b/i, 'only non-locking, non-mutating SELECT statements are allowed'],
          [/\binto\b/i, 'only non-locking, non-mutating SELECT statements are allowed']
        ].freeze

        # @param sql [Object] raw client-provided SQL
        def initialize(sql)
          @sql = sql.to_s
        end

        # Validates the statement against the SELECT-only allowlist.
        #
        # @return [String, nil] an error message when rejected, nil when allowed
        def error
          rule = REJECTION_RULES.find { |pattern, _message| @sql.match?(pattern) }
          rule&.last
        end
      end
    end
  end
end

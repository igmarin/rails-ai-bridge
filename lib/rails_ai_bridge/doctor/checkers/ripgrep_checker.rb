# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      class RipgrepChecker < BaseChecker
        def call
          check(
            "ripgrep",
            system("which rg > /dev/null 2>&1"),
            pass: { message: "rg available for code search" },
            fail: { status: :warn, message: "ripgrep not installed (code search will use slower Ruby fallback)", fix: "Install with `brew install ripgrep` or `apt install ripgrep`" }
          )
        end
      end
    end
  end
end

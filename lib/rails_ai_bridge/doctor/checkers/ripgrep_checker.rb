# frozen_string_literal: true

require 'open3'

module RailsAiBridge
  class Doctor
    module Checkers
      # Verifies +rg+ is available on +PATH+ for fast code search.
      class RipgrepChecker < BaseChecker
        # @return [Doctor::Check] +:pass+ when +rg+ is found; +:warn+ otherwise
        def call
          available = begin
            Open3.capture2('rg', '--version').last.success?
          rescue Errno::ENOENT
            false
          end

          check(
            'ripgrep',
            available,
            pass: { message: 'rg available for code search' },
            fail: { status: :warn, message: 'ripgrep not installed (code search will use slower Ruby fallback)',
                    fix: 'Install with `brew install ripgrep` or `apt install ripgrep`' }
          )
        end
      end
    end
  end
end

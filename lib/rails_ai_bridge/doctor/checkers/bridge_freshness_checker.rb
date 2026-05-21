# frozen_string_literal: true

module RailsAiBridge
  class Doctor
    module Checkers
      # Verifies the freshness of bridge-generated context files.
      class BridgeFreshnessChecker < BaseChecker
        # Accumulator for file scanning results.
        ScanResult = Struct.new(:found_files, :stale_files) do
          def initialize
            super([], [])
          end
        end

        attr_reader :formats

        # @param app [Rails::Application]
        # @param formats [Symbol, Array<Symbol>] formats to check, defaults to all in FORMAT_MAP
        def initialize(app, formats: :all)
          super(app)
          @formats = formats == :all ? RailsAiBridge::Serializers::ContextFileSerializer::FORMAT_MAP.keys : Array(formats)
        end

        # Diagnostic check for bridge file freshness.
        #
        # @return [Doctor::Check] diagnostic outcome
        def call
          output_dir = RailsAiBridge.configuration.output_dir_for(app)
          current_fp = safe_source_fingerprint
          return current_fp if current_fp.is_a?(Doctor::Check)

          scan = scan_files(output_dir, current_fp)
          build_outcome(scan)
        rescue StandardError => error
          check_error('Error checking freshness', error)
        end

        private

        # Safely computes the source fingerprint, returning a warn check on failure.
        #
        # @return [String, Doctor::Check] fingerprint string or error check
        def safe_source_fingerprint
          RailsAiBridge::Fingerprinter.source_fingerprint(app)
        rescue StandardError => error
          check_error('Failed to compute source fingerprint', error)
        end

        # Builds a warn-level check for a given error context.
        #
        # @param msg [String] error description
        # @param error [StandardError] the raised exception
        # @return [Doctor::Check]
        def check_error(msg, error)
          new_check(
            name: 'Bridge file freshness',
            status: :warn,
            message: "#{msg}: #{error.message}",
            fix: 'Run `rails ai:bridge` to regenerate files'
          )
        end

        # Scans all configured format files in the output directory for staleness.
        #
        # @param output_dir [String] bridge file output directory
        # @param current_fp [String] current source fingerprint
        # @return [ScanResult] found and stale file lists
        def scan_files(output_dir, current_fp)
          scan = ScanResult.new
          formats.each do |fmt|
            filename = RailsAiBridge::Serializers::ContextFileSerializer::FORMAT_MAP[fmt]
            next unless filename

            accumulate_file_result(filename, fmt, current_fp, output_dir, scan)
          end
          scan
        end

        # Checks a single file and records it as found (and stale if applicable).
        #
        # @param filename [String] relative filename
        # @param fmt [Symbol] format key
        # @param current_fp [String] current source fingerprint
        # @param output_dir [String] output directory path
        # @param scan [ScanResult] accumulator
        # @return [void]
        # :reek:FeatureEnvy
        def accumulate_file_result(filename, fmt, current_fp, output_dir, scan)
          filepath = File.join(output_dir, filename)
          return unless File.exist?(filepath)

          scan.found_files << filename
          scan.stale_files << filename if stale?(fmt, filepath, current_fp)
        end

        # Checks whether a single file's embedded fingerprint matches the current one.
        #
        # @param fmt [Symbol] format key
        # @param filepath [String] absolute file path
        # @param current_fp [String] current source fingerprint
        # @return [Boolean] +true+ if the file is stale or unreadable
        # :reek:UtilityFunction
        def stale?(fmt, filepath, current_fp)
          content = File.read(filepath)
          RailsAiBridge::FreshnessHeader.extract_fingerprint_for(fmt, content) != current_fp
        rescue StandardError
          true
        end

        # Builds the diagnostic outcome from a scan result.
        #
        # @param scan [ScanResult] file scan results
        # @return [Doctor::Check]
        def build_outcome(scan)
          stale_files = scan.stale_files
          if scan.found_files.empty?
            freshness_check(:warn, 'No bridge files found on disk', 'Run `rails ai:bridge` to generate them')
          elsif stale_files.any?
            freshness_check(:warn, "Stale bridge files: #{stale_files.join(', ')}", 'Run `rails ai:bridge` to regenerate them')
          else
            freshness_check(:pass, 'All generated bridge files are fresh', nil)
          end
        end

        # Builds a check result for freshness validation.
        #
        # @param status [Symbol] check status (+:pass+, +:warn+)
        # @param message [String] description
        # @param fix [String, nil] remediation instructions
        # @return [Doctor::Check]
        def freshness_check(status, message, fix)
          new_check(name: 'Bridge file freshness', status: status, message: message, fix: fix)
        end
      end
    end
  end
end

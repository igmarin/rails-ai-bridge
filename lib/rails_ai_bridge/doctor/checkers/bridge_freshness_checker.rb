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

        def safe_source_fingerprint
          RailsAiBridge::Fingerprinter.source_fingerprint(app)
        rescue StandardError => error
          check_error('Failed to compute source fingerprint', error)
        end

        def check_error(msg, error)
          new_check(
            name: 'Bridge file freshness',
            status: :warn,
            message: "#{msg}: #{error.message}",
            fix: 'Run `rails ai:bridge` to regenerate files'
          )
        end

        def scan_files(output_dir, current_fp)
          scan = ScanResult.new
          formats.each do |fmt|
            filename = RailsAiBridge::Serializers::ContextFileSerializer::FORMAT_MAP[fmt]
            next unless filename

            accumulate_file_result(filename, fmt, current_fp, output_dir, scan)
          end
          scan
        end

        # :reek:FeatureEnvy
        def accumulate_file_result(filename, fmt, current_fp, output_dir, scan)
          filepath = File.join(output_dir, filename)
          return unless File.exist?(filepath)

          scan.found_files << filename
          scan.stale_files << filename if stale?(fmt, filepath, current_fp)
        end

        # :reek:UtilityFunction
        def stale?(fmt, filepath, current_fp)
          content = File.read(filepath)
          RailsAiBridge::FreshnessHeader.extract_fingerprint_for(fmt, content) != current_fp
        rescue StandardError
          true
        end

        def build_outcome(scan)
          if scan.found_files.empty?
            freshness_check(:warn, 'No bridge files found on disk', 'Run `rails ai:bridge` to generate them')
          elsif scan.stale_files.any?
            freshness_check(:warn, "Stale bridge files: #{scan.stale_files.join(', ')}", 'Run `rails ai:bridge` to regenerate them')
          else
            freshness_check(:pass, 'All generated bridge files are fresh', nil)
          end
        end

        def freshness_check(status, message, fix)
          new_check(name: 'Bridge file freshness', status: status, message: message, fix: fix)
        end
      end
    end
  end
end

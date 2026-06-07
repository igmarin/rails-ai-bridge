# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RailsAiBridge::Tools::SearchCode::RipgrepSearch do
  let(:tmpdir) { Dir.mktmpdir }
  let(:root) { tmpdir }

  after { FileUtils.remove_entry(tmpdir) }

  def write_file(relative_path, content)
    full_path = File.join(tmpdir, relative_path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
    full_path
  end

  def make_searcher(pattern:, search_path: nil, file_type: nil, max_results: 50)
    described_class.new(
      pattern: pattern,
      search_path: search_path || tmpdir,
      file_type: file_type,
      max_results: max_results,
      root: root
    )
  end

  describe '#call' do
    # RipgrepSearch delegates to the rg binary via Open3. We stub Open3.capture2
    # throughout this describe block so the suite does not depend on rg being
    # installed in CI. Tests that verify the *command shape* live in CommandBuilder.

    let(:user_rb_path) { File.join(tmpdir, 'app/models/user.rb') }

    before do
      write_file('app/models/user.rb', "class User < ApplicationRecord\nend\n")
      write_file('app/models/admin.rb', "class Admin < User; end\n")
    end

    context 'when ripgrep returns matching results' do
      before do
        rg_output = "#{user_rb_path}:1:class User < ApplicationRecord\n"
        allow(Open3).to receive(:capture2).and_return([rg_output, double(success?: true)])
      end

      it 'returns structured result hashes' do
        results = make_searcher(pattern: 'ApplicationRecord').call

        expect(results).not_to be_empty
        expect(results.first).to include(:file, :line_number, :content)
      end

      it 'strips the root prefix from file paths' do
        results = make_searcher(pattern: 'ApplicationRecord').call

        expect(results.first[:file]).not_to start_with('/')
        expect(results.first[:file]).to eq('app/models/user.rb')
      end

      it 'returns the correct line number as an integer' do
        results = make_searcher(pattern: 'ApplicationRecord').call

        expect(results.first[:line_number]).to eq(1)
        expect(results.first[:line_number]).to be_an(Integer)
      end

      it 'returns the matching line content' do
        results = make_searcher(pattern: 'ApplicationRecord').call

        expect(results.first[:content]).to include('ApplicationRecord')
      end
    end

    context 'when there are no matches' do
      before do
        allow(Open3).to receive(:capture2).and_return(['', double(success?: true)])
      end

      it 'returns an empty array' do
        results = make_searcher(pattern: 'ZZZ_IMPOSSIBLE_MATCH_XYZ').call

        expect(results).to eq([])
      end
    end

    context 'when Open3 raises a StandardError' do
      before do
        allow(Open3).to receive(:capture2).and_raise(StandardError, 'rg not found')
      end

      it 'returns a single error result hash' do
        results = make_searcher(pattern: 'anything').call

        expect(results.length).to eq(1)
        expect(results.first[:file]).to eq('error')
        expect(results.first[:line_number]).to eq(0)
        expect(results.first[:content]).to eq('rg not found')
      end
    end

    context 'with multiple matching files' do
      before do
        admin_rb_path = File.join(tmpdir, 'app/models/admin.rb')
        rg_output = "#{user_rb_path}:1:class User\n#{admin_rb_path}:1:class Admin < User\n"
        allow(Open3).to receive(:capture2).and_return([rg_output, double(success?: true)])
      end

      it 'returns one result per matching line' do
        results = make_searcher(pattern: 'User').call

        expect(results.length).to eq(2)
        expect(results.pluck(:file)).to contain_exactly('app/models/user.rb', 'app/models/admin.rb')
      end
    end

    context 'when output contains lines without the expected format' do
      before do
        # Mix of valid and unparseable lines
        rg_output = "#{user_rb_path}:1:class User\nnot-a-valid-rg-line\n"
        allow(Open3).to receive(:capture2).and_return([rg_output, double(success?: true)])
      end

      it 'silently skips malformed lines' do
        results = make_searcher(pattern: 'User').call

        expect(results.length).to eq(1)
        expect(results.first[:file]).to eq('app/models/user.rb')
      end
    end
  end

  describe RailsAiBridge::Tools::SearchCode::RipgrepSearch::CommandBuilder do
    subject(:builder) do
      described_class.new(
        pattern: pattern,
        search_path: search_path,
        file_type: file_type,
        max_results: max_results
      )
    end

    let(:pattern) { 'class User' }
    let(:search_path) { '/rails/app/models' }
    let(:file_type) { nil }
    let(:max_results) { 50 }

    describe '#build' do
      it 'starts with the rg binary and core flags' do
        cmd = builder.build

        expect(cmd.first).to eq('rg')
        expect(cmd).to include('--no-heading', '--line-number', '--max-count')
      end

      it 'includes the pattern as second-to-last token' do
        cmd = builder.build

        expect(cmd[-2]).to eq(pattern)
      end

      it 'includes the search path as the last token' do
        cmd = builder.build

        expect(cmd.last).to eq(search_path)
      end

      it 'includes the max_results value after --max-count' do
        cmd = builder.build
        idx = cmd.index('--max-count')

        expect(cmd[idx + 1]).to eq('50')
      end

      context 'when file_type is nil' do
        it 'includes --glob flags for each default allowed extension' do
          cmd = builder.build
          allowed = RailsAiBridge::Tools::SearchCode::DEFAULT_ALLOWED_FILE_TYPES

          allowed.each do |ext|
            expect(cmd).to include("*.#{ext}")
          end
        end

        it 'does not include --type-add or --type flags' do
          cmd = builder.build

          expect(cmd).not_to include('--type-add')
          expect(cmd).not_to include('--type')
        end
      end

      context 'when file_type is specified' do
        let(:file_type) { 'rb' }

        it 'includes --type-add and --type custom flags' do
          cmd = builder.build

          expect(cmd).to include('--type-add')
          expect(cmd).to include('--type')
          expect(cmd).to include('custom:*.rb')
          expect(cmd).to include('custom')
        end

        it 'does not add per-extension --glob flags' do
          cmd = builder.build

          expect(cmd).not_to include('*.erb')
        end
      end

      context 'secret file exclusions' do
        it 'includes --glob exclusion for .env files' do
          cmd = builder.build

          expect(cmd).to include('!.env')
        end

        it 'includes --glob exclusion for .pem files' do
          cmd = builder.build

          expect(cmd).to include('!*.pem')
        end

        it 'includes --glob exclusion for .key files' do
          cmd = builder.build

          expect(cmd).to include('!*.key')
        end

        it 'excludes all SECRET_EXCLUDES globs' do
          cmd = builder.build
          excludes = RailsAiBridge::Tools::SearchCode::RipgrepSearch::CommandBuilder::SECRET_EXCLUDES

          excludes.each do |glob|
            expect(cmd).to include("!#{glob}"), "expected cmd to exclude #{glob}"
          end
        end
      end

      context 'excluded_paths from configuration' do
        it 'adds --glob exclusion for each configured excluded path' do
          allow(RailsAiBridge.configuration).to receive(:excluded_paths).and_return(%w[vendor/ node_modules])

          cmd = builder.build

          expect(cmd).to include('!vendor/')
          expect(cmd).to include('!node_modules')
        end
      end
    end
  end
end

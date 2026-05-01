# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::ContextFileSerializer do
  let(:context) { RailsAiBridge.introspect }

  describe '#call' do
    it 'writes files for all formats including split rules' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :all)
        result = serializer.call
        # Main files + split rules/support files for all supported assistants.
        expect(result[:written].size).to be >= 6
        expect(result[:skipped]).to be_empty
      end
    end

    it 'skips unchanged files on second run' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        described_class.new(context, format: :claude).call
        result = described_class.new(context, format: :claude).call
        # 1 main file + 4 .claude/rules/ files = 5 total skipped when unchanged
        expect(result[:skipped].size).to be >= 1
        expect(result[:written]).to be_empty
      end
    end

    it 'writes a single format with split rules' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :claude)
        result = serializer.call
        # 1 CLAUDE.md + 4 .claude/rules/ files (minimum written set varies)
        expect(result[:written].size).to be >= 1
        expect(result[:written].any? { |f| f.end_with?('CLAUDE.md') }).to be true
      end
    end

    it 'generates .claude/rules/ when writing claude format' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :claude)
        result = serializer.call
        claude_rules = result[:written].select { |f| f.include?('.claude/rules/') }
        expect(claude_rules).not_to be_empty
      end
    end

    it 'generates .cursor/rules/ when writing cursor format' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :cursor)
        result = serializer.call
        cursor_rules = result[:written].select { |f| f.include?('.cursor/rules/') }
        expect(cursor_rules).not_to be_empty
      end
    end

    it 'generates .windsurf/rules/ when writing windsurf format' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :windsurf)
        result = serializer.call
        windsurf_rules = result[:written].select { |f| f.include?('.windsurf/rules/') }
        expect(windsurf_rules).not_to be_empty
      end
    end

    it 'generates .github/instructions/ when writing copilot format' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :copilot)
        result = serializer.call
        copilot_instructions = result[:written].select { |f| f.include?('.github/instructions/') }
        expect(copilot_instructions).not_to be_empty
      end
    end

    it 'generates AGENTS.md and .codex support file when writing codex format' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :codex)
        result = serializer.call
        expect(result[:written].any? { |f| f.end_with?('AGENTS.md') }).to be true
        expect(result[:written].any? { |f| f.include?('.codex/README.md') }).to be true
      end
    end

    it 'generates GEMINI.md when writing gemini format' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :gemini)
        result = serializer.call
        expect(result[:written].any? { |f| f.end_with?('GEMINI.md') }).to be true
      end
    end

    it 'can skip split rule generation when split_rules is false' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :cursor, split_rules: false)
        result = serializer.call
        expect(result[:written].none? { |f| f.include?('.cursor/rules/') }).to be true
        expect(result[:written]).not_to be_empty
        expect(result[:written].any? { |f| f.end_with?('.cursorrules') }).to be true
      end
    end

    it 'dispatches cursor format to RulesSerializer' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :cursor)
        result = serializer.call
        cursorrules_file = result[:written].find { |f| f.end_with?('.cursorrules') }
        expect(File.read(cursorrules_file)).to include('Project Rules')
      end
    end

    it 'raises for unknown format' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :bogus)
        expect { serializer.call }.to raise_error(ArgumentError, /Unknown format/)
      end
    end
  end

  describe 'on_conflict option' do
    let(:existing_content) { 'old content' }

    def seed_file(dir, filename, content = existing_content)
      path = File.join(dir, filename)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      path
    end

    it ':overwrite (default) silently overwrites a file whose content changed' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        seed_file(dir, 'CLAUDE.md')
        result = described_class.new(context, format: :claude, split_rules: false).call
        expect(result[:written].any? { |f| f.end_with?('CLAUDE.md') }).to be true
        expect(result[:skipped]).to be_empty
        expect(File.read(File.join(dir, 'CLAUDE.md'))).not_to eq(existing_content)
      end
    end

    it ':skip leaves an existing file unchanged even when content differs' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        seed_file(dir, 'CLAUDE.md')
        result = described_class.new(context, format: :claude, split_rules: false, on_conflict: :skip).call
        expect(result[:written]).to be_empty
        expect(result[:skipped].any? { |f| f.end_with?('CLAUDE.md') }).to be true
        expect(File.read(File.join(dir, 'CLAUDE.md'))).to eq(existing_content)
      end
    end

    it ':prompt writes when the user answers y' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        seed_file(dir, 'CLAUDE.md')
        # Stubs are example-scoped via RSpec's allow; restored automatically after each example.
        allow($stdin).to receive(:gets).and_return("y\n")
        allow($stdout).to receive(:print)
        allow($stdout).to receive(:flush)
        result = described_class.new(context, format: :claude, split_rules: false, on_conflict: :prompt).call
        expect(result[:written].any? { |f| f.end_with?('CLAUDE.md') }).to be true
        expect(File.read(File.join(dir, 'CLAUDE.md'))).not_to eq(existing_content)
      end
    end

    it ':prompt skips when the user answers n' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        seed_file(dir, 'CLAUDE.md')
        allow($stdin).to receive(:gets).and_return("n\n")
        allow($stdout).to receive(:print)
        allow($stdout).to receive(:flush)
        result = described_class.new(context, format: :claude, split_rules: false, on_conflict: :prompt).call
        expect(result[:written]).to be_empty
        expect(result[:skipped].any? { |f| f.end_with?('CLAUDE.md') }).to be true
        expect(File.read(File.join(dir, 'CLAUDE.md'))).to eq(existing_content)
      end
    end

    it 'accepts a proc as a conflict resolver' do
      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        seed_file(dir, 'CLAUDE.md')
        resolver = ->(filepath) { filepath.end_with?('CLAUDE.md') }
        result = described_class.new(context, format: :claude, split_rules: false, on_conflict: resolver).call
        expect(result[:written].any? { |f| f.end_with?('CLAUDE.md') }).to be true
        expect(File.read(File.join(dir, 'CLAUDE.md'))).not_to eq(existing_content)
      end
    end

    it 'accepts any callable (not just Proc) as a conflict resolver' do
      callable_class = Struct.new(:allowed_suffix) do
        def call(filepath) = filepath.end_with?(allowed_suffix)
      end

      Dir.mktmpdir do |dir|
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        seed_file(dir, 'CLAUDE.md')
        result = described_class.new(context, format: :claude, split_rules: false,
                                              on_conflict: callable_class.new('CLAUDE.md')).call
        expect(result[:written].any? { |f| f.end_with?('CLAUDE.md') }).to be true
        expect(File.read(File.join(dir, 'CLAUDE.md'))).not_to eq(existing_content)
      end
    end

    it 'raises ArgumentError for an invalid on_conflict value' do
      expect do
        described_class.new(context, on_conflict: :invalid_value)
      end.to raise_error(ArgumentError, /on_conflict must be/)
    end
  end
end

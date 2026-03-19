# frozen_string_literal: true

require "spec_helper"

RSpec.describe RailsAiContext::Serializers::ContextFileSerializer do
  let(:context) { RailsAiContext.introspect }

  describe "#call" do
    it "writes files for all formats including split rules" do
      Dir.mktmpdir do |dir|
        allow(RailsAiContext.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :all)
        result = serializer.call
        # Main files + split rules/support files for all supported assistants.
        expect(result[:written].size).to be >= 6
        expect(result[:skipped]).to be_empty
      end
    end

    it "skips unchanged files on second run" do
      Dir.mktmpdir do |dir|
        allow(RailsAiContext.configuration).to receive(:output_dir_for).and_return(dir)
        described_class.new(context, format: :claude).call
        result = described_class.new(context, format: :claude).call
        # 1 main file + 2 claude/rules files = 3 total skipped
        expect(result[:skipped].size).to be >= 1
        expect(result[:written]).to be_empty
      end
    end

    it "writes a single format with split rules" do
      Dir.mktmpdir do |dir|
        allow(RailsAiContext.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :claude)
        result = serializer.call
        # 1 CLAUDE.md + 2 .claude/rules/ files = 3
        expect(result[:written].size).to be >= 1
        expect(result[:written].any? { |f| f.end_with?("CLAUDE.md") }).to be true
      end
    end

    it "generates .claude/rules/ when writing claude format" do
      Dir.mktmpdir do |dir|
        allow(RailsAiContext.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :claude)
        result = serializer.call
        claude_rules = result[:written].select { |f| f.include?(".claude/rules/") }
        expect(claude_rules).not_to be_empty
      end
    end

    it "generates .cursor/rules/ when writing cursor format" do
      Dir.mktmpdir do |dir|
        allow(RailsAiContext.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :cursor)
        result = serializer.call
        cursor_rules = result[:written].select { |f| f.include?(".cursor/rules/") }
        expect(cursor_rules).not_to be_empty
      end
    end

    it "generates .windsurf/rules/ when writing windsurf format" do
      Dir.mktmpdir do |dir|
        allow(RailsAiContext.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :windsurf)
        result = serializer.call
        windsurf_rules = result[:written].select { |f| f.include?(".windsurf/rules/") }
        expect(windsurf_rules).not_to be_empty
      end
    end

    it "generates .github/instructions/ when writing copilot format" do
      Dir.mktmpdir do |dir|
        allow(RailsAiContext.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :copilot)
        result = serializer.call
        copilot_instructions = result[:written].select { |f| f.include?(".github/instructions/") }
        expect(copilot_instructions).not_to be_empty
      end
    end

    it "generates AGENTS.md and .codex support file when writing codex format" do
      Dir.mktmpdir do |dir|
        allow(RailsAiContext.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :codex)
        result = serializer.call
        expect(result[:written].any? { |f| f.end_with?("AGENTS.md") }).to be true
        expect(result[:written].any? { |f| f.include?(".codex/README.md") }).to be true
      end
    end

    it "dispatches cursor format to RulesSerializer" do
      Dir.mktmpdir do |dir|
        allow(RailsAiContext.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :cursor)
        result = serializer.call
        cursorrules_file = result[:written].find { |f| f.end_with?(".cursorrules") }
        expect(File.read(cursorrules_file)).to include("Project Rules")
      end
    end

    it "raises for unknown format" do
      Dir.mktmpdir do |dir|
        allow(RailsAiContext.configuration).to receive(:output_dir_for).and_return(dir)
        serializer = described_class.new(context, format: :bogus)
        expect { serializer.call }.to raise_error(ArgumentError, /Unknown format/)
      end
    end
  end
end

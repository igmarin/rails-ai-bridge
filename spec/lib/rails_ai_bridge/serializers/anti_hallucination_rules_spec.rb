# frozen_string_literal: true

require 'spec_helper'

# Anti-hallucination rules injection (issue #252 design, implemented in #253).
#
# Every serializer output carries a shared, consistently-named rules block so
# AI assistants verify against the live app (MCP tools) instead of inventing
# structure. The block is a single section ("## Anti-hallucination rules")
# placed near the top of each markdown output, right after the freshness
# header / document intro, so it survives bottom-trimming in compact mode and
# lives inside the managed region for regeneration. The JSON output carries
# the rules under an "anti_hallucination_rules" key.
RSpec.describe 'anti-hallucination rules injection' do
  let(:heading) { '## Anti-hallucination rules' }
  let(:rule_signature) { 'Empty tool output is information, not permission to invent.' }
  let(:max_top_lines) { 30 }
  let(:context) { RailsAiBridge.introspect }
  let(:providers) { RailsAiBridge::Serializers::Providers }

  around do |example|
    original_flag = RailsAiBridge.configuration.anti_hallucination_rules
    original_mode = RailsAiBridge.configuration.context_mode
    example.run
  ensure
    RailsAiBridge.configuration.anti_hallucination_rules = original_flag
    RailsAiBridge.configuration.context_mode = original_mode
  end

  # Shared example source is a tuple:
  #   [:main, SerializerClass, :compact | :full]
  #   [:split, SerializerClass, 'relative/path']
  shared_examples 'a markdown output carrying the rules block' do |source|
    kind, target, variant = source

    define_method(:payload) do
      case kind
      when :main
        RailsAiBridge.configuration.context_mode = :full if variant == :full
        target.new(context).call
      when :split
        Dir.mktmpdir do |dir|
          target.new(context).call(dir)
          break File.read(File.join(dir, variant))
        end
      end
    end

    it 'includes the rules block when enabled' do
      with_rules(true) do
        expect(payload).to include(heading)
        expect(payload).to include(rule_signature)
      end
    end

    it 'places the rules heading within the first 30 lines' do
      with_rules(true) do
        line = payload.lines.index { |l| l.include?(heading) }
        expect(line).to be < max_top_lines,
                        "expected #{heading.inspect} within the first #{max_top_lines} lines, " \
                        "found at line #{line.inspect}"
      end
    end

    it 'omits the rules block when disabled' do
      with_rules(false) do
        expect(payload).not_to include(heading)
        expect(payload).not_to include(rule_signature)
      end
    end
  end

  def with_rules(enabled)
    RailsAiBridge.configuration.anti_hallucination_rules = enabled
    yield
  end

  # --- 7 main serializers -------------------------------------------------

  describe 'claude (CLAUDE.md)' do
    it_behaves_like 'a markdown output carrying the rules block', [:main, RailsAiBridge::Serializers::Providers::ClaudeSerializer, :compact]
    it_behaves_like 'a markdown output carrying the rules block', [:main, RailsAiBridge::Serializers::Providers::ClaudeSerializer, :full]
  end

  describe 'codex (AGENTS.md)' do
    it_behaves_like 'a markdown output carrying the rules block', [:main, RailsAiBridge::Serializers::Providers::CodexSerializer, :compact]
    it_behaves_like 'a markdown output carrying the rules block', [:main, RailsAiBridge::Serializers::Providers::CodexSerializer, :full]
  end

  describe 'cursor (.cursorrules)' do
    it_behaves_like 'a markdown output carrying the rules block', [:main, RailsAiBridge::Serializers::Providers::RulesSerializer, :compact]
    it_behaves_like 'a markdown output carrying the rules block', [:main, RailsAiBridge::Serializers::Providers::RulesSerializer, :full]
  end

  describe 'devin (.devinrules)' do
    it_behaves_like 'a markdown output carrying the rules block', [:main, RailsAiBridge::Serializers::Providers::DevinSerializer, :compact]
  end

  describe 'copilot (.github/copilot-instructions.md)' do
    it_behaves_like 'a markdown output carrying the rules block', [:main, RailsAiBridge::Serializers::Providers::CopilotSerializer, :compact]
    it_behaves_like 'a markdown output carrying the rules block', [:main, RailsAiBridge::Serializers::Providers::CopilotSerializer, :full]
  end

  describe 'gemini (GEMINI.md)' do
    it_behaves_like 'a markdown output carrying the rules block', [:main, RailsAiBridge::Serializers::Providers::GeminiSerializer, :compact]
    it_behaves_like 'a markdown output carrying the rules block', [:main, RailsAiBridge::Serializers::Providers::GeminiSerializer, :full]
  end

  describe 'json (.ai-context.json)' do
    it 'carries the rules key with the rules array when enabled' do
      with_rules(true) do
        rules = JSON.parse(RailsAiBridge::Serializers::JsonSerializer.new(context).call)['anti_hallucination_rules']
        expect(rules).to be_an(Array)
        expect(rules.join(' ')).to include(rule_signature)
      end
    end

    it 'omits the rules key when disabled' do
      with_rules(false) do
        parsed = JSON.parse(RailsAiBridge::Serializers::JsonSerializer.new(context).call)
        expect(parsed).not_to have_key('anti_hallucination_rules')
      end
    end
  end

  # --- 5 split-rules serializers ------------------------------------------

  describe 'claude_rules (.claude/rules/rails-context.md)' do
    it_behaves_like 'a markdown output carrying the rules block', [:split, RailsAiBridge::Serializers::Providers::ClaudeRulesSerializer, '.claude/rules/rails-context.md']
  end

  describe 'codex_support (.codex/README.md)' do
    it_behaves_like 'a markdown output carrying the rules block', [:split, RailsAiBridge::Serializers::Providers::CodexSupportSerializer, '.codex/README.md']
  end

  describe 'cursor_rules (.cursor/rules/rails-engineering.mdc)' do
    it_behaves_like 'a markdown output carrying the rules block', [:split, RailsAiBridge::Serializers::Providers::CursorRulesSerializer, '.cursor/rules/rails-engineering.mdc']
  end

  describe 'devin_rules (.devin/rules/rails-context.md)' do
    it_behaves_like 'a markdown output carrying the rules block', [:split, RailsAiBridge::Serializers::Providers::DevinRulesSerializer, '.devin/rules/rails-context.md']
  end

  describe 'copilot_instructions (.github/instructions/rails-mcp-tools.instructions.md)' do
    it_behaves_like 'a markdown output carrying the rules block',
                    [:split, RailsAiBridge::Serializers::Providers::CopilotInstructionsSerializer, '.github/instructions/rails-mcp-tools.instructions.md']
  end

  # --- managed-region placement -------------------------------------------

  it 'keeps the rules block inside the managed region of generated files' do
    Dir.mktmpdir do |dir|
      with_rules(true) do
        allow(RailsAiBridge.configuration).to receive(:output_dir_for).and_return(dir)
        RailsAiBridge::Serializers::ContextFileSerializer.new(
          context, fingerprint: 'a1b2c3d4e5f6', format: :claude, managed_region: true
        ).call
      end

      generated = RailsAiBridge::Serializers::ManagedRegion.extract(File.read(File.join(dir, 'CLAUDE.md')))
      expect(generated).to include(heading)
    end
  end
end

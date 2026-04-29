# frozen_string_literal: true

require 'spec_helper'
require 'rails/generators'
require 'generators/rails_ai_bridge/install/install_generator'

RSpec.describe RailsAiBridge::Generators::InstallGenerator do
  let(:destination_root) { Dir.mktmpdir }
  let(:generator) { build_generator }

  def build_generator(args = [], **thor_opts)
    local_opts = thor_opts.compact.transform_keys(&:to_s)
    described_class.new(args, local_opts, { destination_root: destination_root })
  end

  after do
    FileUtils.remove_entry(destination_root)
  end

  describe '#create_initializer' do
    it 'documents the current preset sizes' do
      generator.create_initializer

      content = File.read(File.join(destination_root, 'config/initializers/rails_ai_bridge.rb'))

      expect(content).to include(':standard  — 9 core introspectors')
      expect(content).to include(':full      — all 27 introspectors')
    end

    it 'documents the :regulated preset' do
      generator.create_initializer
      content = File.read(File.join(destination_root, 'config/initializers/rails_ai_bridge.rb'))
      expect(content).to include(':regulated')
    end

    it 'documents excluded_tables' do
      generator.create_initializer
      content = File.read(File.join(destination_root, 'config/initializers/rails_ai_bridge.rb'))
      expect(content).to include('excluded_tables')
    end

    it 'documents disabled_introspection_categories' do
      generator.create_initializer
      content = File.read(File.join(destination_root, 'config/initializers/rails_ai_bridge.rb'))
      expect(content).to include('disabled_introspection_categories')
    end

    it 'documents mcp_token_resolver' do
      generator.create_initializer
      content = File.read(File.join(destination_root, 'config/initializers/rails_ai_bridge.rb'))
      expect(content).to include('mcp_token_resolver')
    end

    it 'documents mcp_jwt_decoder' do
      generator.create_initializer
      content = File.read(File.join(destination_root, 'config/initializers/rails_ai_bridge.rb'))
      expect(content).to include('mcp_jwt_decoder')
    end
  end

  describe '#show_instructions' do
    it 'includes gemini in format list and bridge files' do
      expect { generator.show_instructions }.to output(/gemini/).to_stdout
      expect { generator.show_instructions }.to output(/Gemini.*→ GEMINI\.md/).to_stdout
    end

    it 'shows minimal output when --skip-context is provided' do
      skip_generator = build_generator([], skip_context: true)
      expect { skip_generator.show_instructions }.to output(/rails-ai-bridge installed!.*rails ai:bridge/).to_stdout
      expect { skip_generator.show_instructions }.not_to output(/Bridge files per tool/).to_stdout
    end

    it 'mentions the chosen profile when not custom' do
      minimal_generator = build_generator([], profile: 'minimal')
      allow(minimal_generator).to receive(:say)
      minimal_generator.show_instructions

      expect(minimal_generator).to have_received(:say).with(a_string_matching(/Profile: minimal/))
    end
  end

  describe '#generate_context_files profiles' do
    let(:minimal_formats) { %i[claude cursor windsurf copilot gemini] }

    it 'skips context generation when profile is mcp' do
      generator = build_generator([], profile: 'mcp')
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:say)

      expect(RailsAiBridge).not_to receive(:generate_context)

      generator.generate_context_files
    end

    it 'generates minimal profile with split rules disabled' do
      generator = build_generator([], profile: 'minimal')
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:say)

      expect(RailsAiBridge).to receive(:generate_context).with(format: minimal_formats, split_rules: false).and_return({ written: [], skipped: [] })

      generator.generate_context_files
    end

    it 'allows selecting minimal profile interactively' do
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:say)
      allow(generator).to receive_messages(yes?: true, ask: 'custom') # Select custom to go to per-format prompts
      allow(generator).to receive(:yes?).with('Generate CLAUDE.md? (y/n)').and_return(true)
      allow(generator).to receive(:yes?).with('Generate .cursorrules? (y/n)').and_return(true)
      allow(generator).to receive(:yes?).with('Generate .windsurfrules? (y/n)').and_return(true)
      allow(generator).to receive(:yes?).with('Generate .github/copilot-instructions.md? (y/n)').and_return(true)
      allow(generator).to receive(:yes?).with('Generate GEMINI.md? (y/n)').and_return(true)
      allow(generator).to receive(:yes?).with('Generate AGENTS.md? (y/n)').and_return(false)

      expect(RailsAiBridge).to receive(:generate_context).with(format: minimal_formats, split_rules: true).and_return({ written: [], skipped: [] })

      generator.generate_context_files
    end

    it 'generates full profile with split rules enabled' do
      generator = build_generator([], profile: 'full')
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:say)

      full_formats = RailsAiBridge::Serializers::ContextFileSerializer::FORMAT_MAP.keys
      expect(RailsAiBridge).to receive(:generate_context).with(format: full_formats, split_rules: true).and_return({ written: [], skipped: [] })

      generator.generate_context_files
    end

    it 'shows a red error and returns early when --profile is invalid' do
      generator = build_generator([], profile: 'bogus')
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:say)

      generator.generate_context_files

      expect(generator).to have_received(:say).with(a_string_including("Unknown --profile 'bogus'"), :red)
      expect(generator).not_to have_received(:say).with(a_string_including('Falling back to custom'), anything)
    end

    it 'prefers --skip-context over profile' do
      generator = build_generator([], profile: 'full', skip_context: true)
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:say)

      expect(RailsAiBridge).not_to receive(:generate_context)

      generator.generate_context_files
    end
  end

  describe '#generate_context_files' do
    before do
      allow(generator).to receive(:ask).and_return('')
    end

    it 'reports written and skipped files separately' do
      allow(RailsAiBridge).to receive(:generate_context).and_return({
                                                                      written: ['CLAUDE.md'],
                                                                      skipped: ['.cursorrules']
                                                                    })
      allow(generator).to receive(:say)
      allow(generator).to receive(:yes?).and_return(true)

      generator.generate_context_files

      expect(generator).to have_received(:say).with('  Created CLAUDE.md', :green)
      expect(generator).to have_received(:say).with('  Unchanged .cursorrules', :blue)
    end

    it 'calls generate_context with full format list when Rails.application is available (characterization test)' do
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:yes?).and_return(true)
      allow(RailsAiBridge).to receive(:generate_context).with(format: %i[claude cursor windsurf copilot gemini codex], split_rules: true).and_return({
                                                                                                                                                       written: [],
                                                                                                                                                       skipped: []
                                                                                                                                                     })
      allow(generator).to receive(:say)

      generator.generate_context_files

      expect(RailsAiBridge).to have_received(:generate_context).with(format: %i[claude cursor windsurf copilot gemini codex], split_rules: true)
    end
  end

  # --------------------------------------------------------------------------
  # Characterization tests for 4 refactoring targets
  # --------------------------------------------------------------------------

  describe '#create_mcp_config' do
    it 'creates .mcp.json with correct server definition' do
      generator.create_mcp_config

      content = File.read(File.join(destination_root, '.mcp.json'))
      parsed = JSON.parse(content)

      expect(parsed['mcpServers']['rails-ai-bridge']['command']).to eq('bundle')
      expect(parsed['mcpServers']['rails-ai-bridge']['args']).to eq(%w[exec rails ai:serve])
    end

    it 'respects --pretend (dry-run) and does not write .mcp.json' do
      pretend_generator = build_generator([], pretend: true)

      pretend_generator.create_mcp_config

      expect(File).not_to exist(File.join(destination_root, '.mcp.json'))
    end
  end

  describe '#create_assistant_overrides_template' do
    it 'creates overrides.md stub with omit-merge comment' do
      generator.create_assistant_overrides_template

      stub_path = File.join(destination_root, 'config', 'rails_ai_bridge', 'overrides.md')
      expect(File.exist?(stub_path)).to be true
      content = File.read(stub_path)
      expect(content).to include('rails-ai-bridge:omit-merge')
    end

    it 'does not overwrite existing overrides.md' do
      dir = File.join(destination_root, 'config', 'rails_ai_bridge')
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'overrides.md'), 'team rules here')

      generator.create_assistant_overrides_template

      content = File.read(File.join(dir, 'overrides.md'))
      expect(content).to eq('team rules here')
    end

    it 'respects --pretend (dry-run) and does not create directory or files' do
      pretend_generator = build_generator([], pretend: true)

      pretend_generator.create_assistant_overrides_template

      dir = File.join(destination_root, 'config', 'rails_ai_bridge')
      expect(File).not_to exist(dir)
    end
  end

  describe '#add_to_gitignore' do
    it 'appends .ai-context.json to .gitignore when missing' do
      gitignore_path = File.join(destination_root, '.gitignore')
      File.write(gitignore_path, "node_modules/\n")

      generator.add_to_gitignore

      content = File.read(gitignore_path)
      expect(content).to include('.ai-context.json')
      expect(content).to include('rails-ai-bridge')
    end

    it 'does not duplicate .ai-context.json if already present' do
      gitignore_path = File.join(destination_root, '.gitignore')
      File.write(gitignore_path, "node_modules/\n.ai-context.json\n")

      generator.add_to_gitignore

      content = File.read(gitignore_path)
      occurrences = content.scan('.ai-context.json').length
      expect(occurrences).to eq(1)
    end

    it 'skips silently when .gitignore does not exist' do
      expect { generator.add_to_gitignore }.not_to raise_error
      expect(File).not_to exist(File.join(destination_root, '.gitignore'))
    end

    it 'respects --pretend (dry-run) and does not modify .gitignore' do
      gitignore_path = File.join(destination_root, '.gitignore')
      File.write(gitignore_path, "node_modules/\n")

      pretend_generator = build_generator([], pretend: true)
      pretend_generator.add_to_gitignore

      content = File.read(gitignore_path)
      expect(content).not_to include('.ai-context.json')
    end

    it 'handles empty .gitignore' do
      gitignore_path = File.join(destination_root, '.gitignore')
      File.write(gitignore_path, '')

      generator.add_to_gitignore

      content = File.read(gitignore_path)
      expect(content).to include('.ai-context.json')
    end
  end

  describe '#generate_context_files error handling' do
    before do
      allow(generator).to receive(:ask).and_return('')
    end

    it 'gracefully handles generate_context raising an error' do
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:yes?).and_return(true)
      allow(RailsAiBridge).to receive(:generate_context).and_raise(StandardError, 'introspection failed')
      allow(generator).to receive(:say)

      expect { generator.generate_context_files }.not_to raise_error
    end

    it 'reports error message when generate_context fails' do
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:yes?).and_return(true)
      allow(RailsAiBridge).to receive(:generate_context).and_raise(StandardError, 'introspection failed')
      allow(generator).to receive(:say)

      generator.generate_context_files

      expect(generator).to have_received(:say).with('  Context generation failed (StandardError). Run `rails ai:bridge` after install to retry.', :red)
    end

    it 'skips when Rails.application is nil' do
      allow(Rails).to receive(:application).and_return(nil)
      allow(generator).to receive(:say)

      generator.generate_context_files

      expect(generator).to have_received(:say).with('  Skipped (Rails app not fully loaded). Run `rails ai:bridge` after install.', :yellow)
    end
  end

  # --------------------------------------------------------------------------
  # Interactive prompt behavior (TDD - these should fail initially)
  # --------------------------------------------------------------------------
  describe '#generate_context_files interactive mode' do
    let(:generator_with_options) { build_generator([], skip_context: false) }

    it 'skips context generation when --skip-context flag is provided' do
      skip_generator = build_generator([], skip_context: true)
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(RailsAiBridge).to receive(:generate_context)
      allow(skip_generator).to receive(:say)

      skip_generator.generate_context_files

      expect(RailsAiBridge).not_to have_received(:generate_context)
    end

    it 'prompts user when no --skip-context flag and Rails.application is available' do
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:ask).and_return('')
      allow(generator).to receive(:yes?).with('Generate AI assistant context files? (y/n)').and_return(false)
      allow(generator).to receive(:say)

      generator.generate_context_files

      expect(generator).to have_received(:yes?).with('Generate AI assistant context files? (y/n)')
    end

    it 'does not call generate_context when user declines initial prompt' do
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:ask).and_return('')
      allow(generator).to receive(:yes?).with('Generate AI assistant context files? (y/n)').and_return(false)
      allow(RailsAiBridge).to receive(:generate_context)
      allow(generator).to receive(:say)

      generator.generate_context_files

      expect(RailsAiBridge).not_to have_received(:generate_context)
    end

    it 'prompts for each format when user accepts initial prompt' do
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:ask).and_return('')
      allow(generator).to receive(:yes?).with('Generate AI assistant context files? (y/n)').and_return(true)
      allow(generator).to receive(:yes?).with('Generate CLAUDE.md? (y/n)').and_return(false)
      allow(generator).to receive(:yes?).with('Generate .cursorrules? (y/n)').and_return(false)
      allow(generator).to receive(:yes?).with('Generate .windsurfrules? (y/n)').and_return(false)
      allow(generator).to receive(:yes?).with('Generate .github/copilot-instructions.md? (y/n)').and_return(false)
      allow(generator).to receive(:yes?).with('Generate GEMINI.md? (y/n)').and_return(false)
      allow(generator).to receive(:yes?).with('Generate AGENTS.md? (y/n)').and_return(false)
      allow(RailsAiBridge).to receive(:generate_context)
      allow(generator).to receive(:say)

      generator.generate_context_files

      expect(generator).to have_received(:yes?).with('Generate AI assistant context files? (y/n)')
      expect(generator).to have_received(:yes?).with('Generate CLAUDE.md? (y/n)')
      expect(generator).to have_received(:yes?).with('Generate .cursorrules? (y/n)')
      expect(generator).to have_received(:yes?).with('Generate .windsurfrules? (y/n)')
      expect(generator).to have_received(:yes?).with('Generate .github/copilot-instructions.md? (y/n)')
      expect(generator).to have_received(:yes?).with('Generate GEMINI.md? (y/n)')
      expect(generator).to have_received(:yes?).with('Generate AGENTS.md? (y/n)')
    end

    it 'passes selected formats to generate_context when user accepts specific formats' do
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:ask).and_return('')
      allow(generator).to receive(:yes?).with('Generate AI assistant context files? (y/n)').and_return(true)
      allow(generator).to receive(:yes?).with('Generate CLAUDE.md? (y/n)').and_return(true)
      allow(generator).to receive(:yes?).with('Generate .cursorrules? (y/n)').and_return(true)
      allow(generator).to receive(:yes?).with('Generate .windsurfrules? (y/n)').and_return(false)
      allow(generator).to receive(:yes?).with('Generate .github/copilot-instructions.md? (y/n)').and_return(false)
      allow(generator).to receive(:yes?).with('Generate GEMINI.md? (y/n)').and_return(false)
      allow(generator).to receive(:yes?).with('Generate AGENTS.md? (y/n)').and_return(false)
      allow(RailsAiBridge).to receive(:generate_context).with(format: %i[claude cursor], split_rules: true).and_return({ written: [], skipped: [] })
      allow(generator).to receive(:say)

      generator.generate_context_files

      expect(RailsAiBridge).to have_received(:generate_context).with(format: %i[claude cursor], split_rules: true)
    end

    it 'skips generate_context when user accepts initial prompt but selects no formats' do
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(generator).to receive(:ask).and_return('')
      allow(generator).to receive(:yes?).with('Generate AI assistant context files? (y/n)').and_return(true)
      allow(generator).to receive(:yes?).with('Generate CLAUDE.md? (y/n)').and_return(false)
      allow(generator).to receive(:yes?).with('Generate .cursorrules? (y/n)').and_return(false)
      allow(generator).to receive(:yes?).with('Generate .windsurfrules? (y/n)').and_return(false)
      allow(generator).to receive(:yes?).with('Generate .github/copilot-instructions.md? (y/n)').and_return(false)
      allow(generator).to receive(:yes?).with('Generate GEMINI.md? (y/n)').and_return(false)
      allow(generator).to receive(:yes?).with('Generate AGENTS.md? (y/n)').and_return(false)
      allow(RailsAiBridge).to receive(:generate_context)
      allow(generator).to receive(:say)

      generator.generate_context_files

      expect(RailsAiBridge).not_to have_received(:generate_context)
    end
  end

  describe '#create_initializer JWT comment scope' do
    it 'documents broad JWT error handling (not just DecodeError)' do
      generator.create_initializer

      content = File.read(File.join(destination_root, 'config/initializers/rails_ai_bridge.rb'))

      expect(content).to include('JWT::DecodeError')
      expect(content).to include('JWT::ExpiredSignature')
      expect(content).to include('JWT::ImmatureSignature')
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'
require 'rails/generators'
require 'generators/rails_ai_bridge/install/install_generator'

RSpec.describe RailsAiBridge::Generators::InstallGenerator do
  let(:destination_root) { Dir.mktmpdir }
  let(:generator) { described_class.new([], {}, destination_root: destination_root) }

  after do
    FileUtils.remove_entry(destination_root)
  end

  describe '#create_initializer' do
    it 'documents the current preset sizes' do
      generator.create_initializer

      content = File.read(File.join(destination_root, 'config/initializers/rails_ai_bridge.rb'))

      expect(content).to include(':standard  — 9 core introspectors')
      expect(content).to include(':full      — all 26 introspectors')
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
    it 'includes gemini instructions' do
      expect { generator.show_instructions }.to output(/rails ai:bridge:gemini/).to_stdout
      expect { generator.show_instructions }.to output(/Gemini         → GEMINI\.md/).to_stdout
    end
  end

  describe '#generate_context_files' do
    it 'reports written and skipped files separately' do
      allow(RailsAiBridge).to receive(:generate_context).and_return({
                                                                      written: ['CLAUDE.md'],
                                                                      skipped: ['.cursorrules']
                                                                    })
      allow(generator).to receive(:say)

      generator.generate_context_files

      expect(generator).to have_received(:say).with('  Created CLAUDE.md', :green)
      expect(generator).to have_received(:say).with('  Unchanged .cursorrules', :blue)
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
      pretend_generator = described_class.new(['--pretend'], destination_root: destination_root)

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
      pretend_generator = described_class.new(['--pretend'], destination_root: destination_root)

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
    end

    it 'respects --pretend (dry-run) and does not modify .gitignore' do
      gitignore_path = File.join(destination_root, '.gitignore')
      File.write(gitignore_path, "node_modules/\n")

      pretend_generator = described_class.new(['--pretend'], destination_root: destination_root)
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
    it 'gracefully handles generate_context raising an error' do
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(RailsAiBridge).to receive(:generate_context).and_raise(StandardError, 'introspection failed')
      allow(generator).to receive(:say)

      expect { generator.generate_context_files }.not_to raise_error
    end

    it 'reports error message when generate_context fails' do
      allow(Rails).to receive(:application).and_return(double('App'))
      allow(RailsAiBridge).to receive(:generate_context).and_raise(StandardError, 'introspection failed')
      allow(generator).to receive(:say)

      generator.generate_context_files

      expect(generator).to have_received(:say).with('  Error generating context: introspection failed', :red)
      expect(generator).to have_received(:say).with('  Run `rails ai:bridge` after install to retry.', :yellow)
    end

    it 'skips when Rails.application is nil' do
      allow(Rails).to receive(:application).and_return(nil)
      allow(generator).to receive(:say)

      generator.generate_context_files

      expect(generator).to have_received(:say).with('  Skipped (Rails app not fully loaded). Run `rails ai:bridge` after install.', :yellow)
    end
  end

  describe '#create_initializer JWT comment scope' do
    it 'documents broad JWT error handling (not just DecodeError)' do
      generator.create_initializer

      content = File.read(File.join(destination_root, 'config/initializers/rails_ai_bridge.rb'))

      # Fix #3: initializer comment should rescue JWT::DecodeError,
      # JWT::ExpiredSignature, and JWT::ImmatureSignature (not just DecodeError).
      expect(content).to include('JWT::DecodeError, JWT::ExpiredSignature, JWT::ImmatureSignature')
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/registry/lockfile'

RSpec.describe RailsAiBridge::Registry::Lockfile do
  let(:entry) do
    described_class::Entry.new(
      pack_name: 'core',
      source: 'igmarin/ruby-core-skills',
      ref: 'v1.0.0',
      commit_sha: 'abc123'
    )
  end

  describe '.load' do
    it 'returns an empty lockfile when path is nil' do
      lockfile = described_class.load(nil)
      expect(lockfile).not_to be_any
    end

    it 'returns an empty lockfile when the file does not exist' do
      lockfile = described_class.load('/nonexistent/directory.lock')
      expect(lockfile).not_to be_any
    end

    it 'parses a valid lockfile' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'directory.lock')
        File.write(
          path,
          JSON.generate(
            'core' => {
              'pack_name' => 'core',
              'source' => 'igmarin/ruby-core-skills',
              'ref' => 'v1.0.0',
              'commit_sha' => 'abc123'
            }
          )
        )

        lockfile = described_class.load(path)
        expect(lockfile).to be_any
        expect(lockfile.entry('core').commit_sha).to eq('abc123')
      end
    end

    it 'raises on invalid JSON' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'directory.lock')
        File.write(path, 'not json')

        expect { described_class.load(path) }.to raise_error(ArgumentError, /Invalid lockfile JSON/)
      end
    end
  end

  describe '#write' do
    it 'writes the lockfile as JSON' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'directory.lock')
        lockfile = described_class.new('core' => entry)

        lockfile.write(path)

        parsed = JSON.parse(File.read(path))
        expect(parsed['core']['commit_sha']).to eq('abc123')
        expect(parsed['core']['source']).to eq('igmarin/ruby-core-skills')
      end
    end
  end

  describe '.generate' do
    it 'resolves every pack and records its commit SHA' do
      source_resolver = double('source_resolver')
      pack_def = double('pack_def', source: 'igmarin/ruby-core-skills', ref: 'v1.0.0')
      manifest = double('manifest', packs: { 'core' => pack_def })

      allow(source_resolver).to receive(:resolve).with('igmarin/ruby-core-skills', ref: 'v1.0.0').and_return('/tmp/core')
      allow(source_resolver).to receive(:current_commit).with('/tmp/core').and_return('def456')

      entries = described_class.generate(manifest, source_resolver)

      expect(entries['core'].commit_sha).to eq('def456')
    end
  end
end

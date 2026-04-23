# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Watcher::WatchDirectories do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmpdir) }

  describe '.resolve' do
    it 'returns absolute paths only for patterns that exist' do
      FileUtils.mkdir_p(File.join(tmpdir, 'app', 'models'))
      FileUtils.mkdir_p(File.join(tmpdir, 'config'))

      paths = described_class.resolve(tmpdir)

      expect(paths).to include(File.join(tmpdir, 'app', 'models'))
      expect(paths).to include(File.join(tmpdir, 'config'))
      expect(paths).not_to include(File.join(tmpdir, 'app', 'controllers'))
    end

    it 'accepts a custom patterns list' do
      FileUtils.mkdir_p(File.join(tmpdir, 'lib', 'tasks'))

      paths = described_class.resolve(tmpdir, patterns: %w[lib/tasks app/missing])

      expect(paths).to eq([File.join(tmpdir, 'lib', 'tasks')])
    end

    it 'returns an empty array when nothing matches' do
      expect(described_class.resolve(tmpdir)).to eq([])
    end
  end
end

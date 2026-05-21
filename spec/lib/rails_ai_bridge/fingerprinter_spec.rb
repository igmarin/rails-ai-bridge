# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe RailsAiBridge::Fingerprinter do
  let(:tmpdir) { Dir.mktmpdir }
  let(:app) { instance_double(Rails::Application, root: Pathname.new(tmpdir)) }

  after { FileUtils.remove_entry(tmpdir) }

  describe '.compute' do
    it 'returns a hex digest string' do
      result = described_class.compute(Rails.application)
      expect(result).to match(/\A[a-f0-9]{64}\z/)
    end

    it 'returns the same value on repeated calls with no changes' do
      a = described_class.compute(Rails.application)
      b = described_class.compute(Rails.application)
      expect(a).to eq(b)
    end
  end

  describe '.changed?' do
    it 'returns false when fingerprint matches current snapshot' do
      current = described_class.compute(Rails.application)
      expect(described_class.changed?(Rails.application, current)).to be false
    end

    it 'returns true when fingerprint differs from current snapshot' do
      expect(described_class.changed?(Rails.application, 'stale_fingerprint_xyz')).to be true
    end
  end

  describe '.source_fingerprint' do
    context 'when db/schema.rb and config/routes.rb are missing' do
      it 'returns a 12-character hex fingerprint of empty inputs' do
        fingerprint = described_class.source_fingerprint(app)
        expect(fingerprint).to match(/\A[a-f0-9]{12}\z/)
        combined = "=== structure.sql ===\n\n---\n=== routes.rb ===\n\n---\n"
        expect(fingerprint).to eq(Digest::SHA256.hexdigest(combined)[0...12])
      end
    end

    context 'when db/schema.rb exists' do
      before do
        FileUtils.mkdir_p(File.join(tmpdir, 'db'))
        FileUtils.mkdir_p(File.join(tmpdir, 'config'))
        File.write(File.join(tmpdir, 'db', 'schema.rb'), 'schema content')
        File.write(File.join(tmpdir, 'config', 'routes.rb'), 'routes content')
      end

      it 'hashes the schema and routes content in order' do
        combined = "=== schema.rb ===\nschema content\n---\n=== routes.rb ===\nroutes content\n---\n"
        expected = Digest::SHA256.hexdigest(combined)[0...12]
        expect(described_class.source_fingerprint(app)).to eq(expected)
      end

      it 'detects content changes' do
        fp1 = described_class.source_fingerprint(app)
        File.write(File.join(tmpdir, 'db', 'schema.rb'), 'schema content updated')
        fp2 = described_class.source_fingerprint(app)
        expect(fp1).not_to eq(fp2)
      end
    end

    context 'when db/structure.sql exists instead of db/schema.rb' do
      before do
        FileUtils.mkdir_p(File.join(tmpdir, 'db'))
        FileUtils.mkdir_p(File.join(tmpdir, 'config'))
        File.write(File.join(tmpdir, 'db', 'structure.sql'), 'sql content')
        File.write(File.join(tmpdir, 'config', 'routes.rb'), 'routes content')
      end

      it 'uses db/structure.sql as the schema source' do
        combined = "=== structure.sql ===\nsql content\n---\n=== routes.rb ===\nroutes content\n---\n"
        expected = Digest::SHA256.hexdigest(combined)[0...12]
        expect(described_class.source_fingerprint(app)).to eq(expected)
      end
    end

    context 'when both db/schema.rb and db/structure.sql exist' do
      before do
        FileUtils.mkdir_p(File.join(tmpdir, 'db'))
        File.write(File.join(tmpdir, 'db', 'schema.rb'), 'schema wins')
        File.write(File.join(tmpdir, 'db', 'structure.sql'), 'sql loses')
      end

      it 'prefers db/schema.rb over db/structure.sql' do
        combined = "=== schema.rb ===\nschema wins\n---\n=== routes.rb ===\n\n---\n"
        expected = Digest::SHA256.hexdigest(combined)[0...12]
        expect(described_class.source_fingerprint(app)).to eq(expected)
      end
    end
  end
end

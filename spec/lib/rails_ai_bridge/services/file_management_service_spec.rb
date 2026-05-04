# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/services/file_management_service'
require 'fileutils'

RSpec.describe RailsAiBridge::Services::FileManagementService do
  let(:test_dir) { Rails.root.join('tmp/rails_ai_bridge_test').to_s }
  let(:test_file) { File.join(test_dir, 'test_file.txt') }

  before do
    FileUtils.mkdir_p(test_dir)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe '.call' do
    it 'writes content to file successfully' do
      result = described_class.call(:write, path: test_file, content: 'test content')

      expect(result.success?).to be(true)
      expect(File.exist?(test_file)).to be(true)
      expect(File.read(test_file)).to eq('test content')
    end

    it 'reads content from file successfully' do
      File.write(test_file, 'existing content')

      result = described_class.call(:read, path: test_file)

      expect(result.success?).to be(true)
      expect(result.data).to eq('existing content')
    end

    it 'deletes file successfully' do
      File.write(test_file, 'content')
      expect(File.exist?(test_file)).to be(true)

      result = described_class.call(:delete, path: test_file)

      expect(result.success?).to be(true)
      expect(File.exist?(test_file)).to be(false)
    end

    it 'handles file not found errors' do
      missing = File.join(test_dir, 'no_such_file.txt')

      result = described_class.call(:read, path: missing)

      expect(result.failure?).to be(true)
      expect(result.errors.first).to match(/No such file or directory/)
    end

    it 'handles permission errors gracefully' do
      probe = Rails.root.join('tmp/permission_probe.txt').to_s
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, 'Permission denied')

      result = described_class.call(:write, path: probe, content: 'content')

      expect(result.failure?).to be(true)
      expect(result.errors.first).to match(/Permission denied/)
    end

    it 'returns failure when operation is nil' do
      result = described_class.call(nil, path: test_file)

      expect(result.failure?).to be(true)
      expect(result.errors).to eq(['Operation cannot be nil'])
    end
  end

  describe '#call' do
    subject { described_class.new }

    it 'returns failure when operation is nil' do
      result = subject.call(nil, path: test_file)

      expect(result.failure?).to be(true)
      expect(result.errors).to eq(['Operation cannot be nil'])
    end

    it 'supports write operation' do
      path = File.join(test_dir, 'write_test.txt')
      result = subject.call(:write, path: path, content: 'written')

      expect(result.success?).to be(true)
      expect(File.read(path)).to eq('written')
    end

    it 'supports read operation' do
      test_read_file = File.join(test_dir, 'read_test.txt')
      File.write(test_read_file, 'readable content')

      result = subject.call(:read, path: test_read_file)

      expect(result.success?).to be(true)
      expect(result.data).to eq('readable content')
    end

    it 'supports delete operation' do
      test_delete_file = File.join(test_dir, 'delete_test.txt')
      File.write(test_delete_file, 'content')

      result = subject.call(:delete, path: test_delete_file)

      expect(result.success?).to be(true)
      expect(File.exist?(test_delete_file)).to be(false)
    end

    it 'supports file existence check' do
      existing_file = File.join(test_dir, 'existing.txt')
      File.write(existing_file, 'content')

      result = subject.call(:exist?, path: existing_file)

      expect(result.success?).to be(true)
      expect(result.data).to be(true)
    end

    it 'returns false for non-existent files' do
      missing = File.join(test_dir, 'ghost.txt')

      result = subject.call(:exist?, path: missing)

      expect(result.success?).to be(true)
      expect(result.data).to be(false)
    end
  end

  describe 'file operations' do
    it 'creates directories if needed for write' do
      nested_path = File.join(test_dir, 'nested', 'dir', 'file.txt')

      result = described_class.call(:write, path: nested_path, content: 'nested content')

      expect(result.success?).to be(true)
      expect(File.exist?(nested_path)).to be(true)
    end

    it 'handles directory creation errors' do
      nested = Rails.root.join('tmp/perm_nested/file.txt').to_s
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, 'Permission denied')

      result = described_class.call(:write, path: nested, content: 'content')

      expect(result.failure?).to be(true)
      expect(result.errors.first).to match(/Permission denied/)
    end
  end

  describe 'path validation' do
    it 'rejects absolute paths outside the allowed base' do
      result = described_class.call(:read, path: '/etc/passwd')

      expect(result.failure?).to be(true)
      expect(result.errors.first).to match(/Path not allowed/)
    end

    it 'rejects relative paths that resolve outside the allowed base' do
      result = described_class.call(:read, path: '../../../config/database.yml')

      expect(result.failure?).to be(true)
      expect(result.errors.first).to match(/Path not allowed/)
    end

    it 'rejects symlinks pointing outside the allowed base' do
      outside_file = File.join(Dir.tmpdir, "rails-ai-bridge-outside-#{SecureRandom.hex}.txt")
      File.write(outside_file, 'sensitive data')

      symlink_path = File.join(test_dir, 'unsafe_symlink.txt')
      File.symlink(outside_file, symlink_path)

      begin
        result = described_class.call(:read, path: symlink_path)
        expect(result.failure?).to be(true)
        expect(result.errors.first).to match(/Path not allowed/)
      ensure
        FileUtils.rm_f(outside_file)
        FileUtils.rm_f(symlink_path)
      end
    end

    it 'rejects an empty path' do
      result = described_class.call(:read, path: '')

      expect(result.failure?).to be(true)
      expect(result.errors.first).to match(/path must be non-empty/)
    end

    it 'allows paths relative to Rails.root' do
      rel = File.join('tmp', 'rails_ai_bridge_test', 'relative_ok.txt')
      full = Rails.root.join(rel).to_s
      FileUtils.mkdir_p(File.dirname(full))

      result = described_class.call(:write, path: rel, content: 'ok')

      expect(result.success?).to be(true)
      expect(File.read(full)).to eq('ok')
    end
  end

  describe 'result format' do
    it 'returns Service::Result for all operations' do
      path = File.join(test_dir, 'result_test.txt')
      write_result = described_class.call(:write, path: path, content: 'test')
      expect(write_result).to be_a(RailsAiBridge::Service::Result)

      read_result = described_class.call(:read, path: path)
      expect(read_result).to be_a(RailsAiBridge::Service::Result)

      delete_result = described_class.call(:delete, path: path)
      expect(delete_result).to be_a(RailsAiBridge::Service::Result)
    end
  end
end

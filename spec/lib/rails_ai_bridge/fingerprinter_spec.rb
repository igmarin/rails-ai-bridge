# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Fingerprinter do
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

    it 'detects changes to .rake files' do
      before = described_class.compute(Rails.application)
      rake_file = Rails.root.join('lib/tasks/example.rake').to_s
      original_mtime = File.mtime(rake_file)

      # Touch the file to change mtime
      FileUtils.touch(rake_file)
      after = described_class.compute(Rails.application)

      # Restore original mtime
      File.utime(original_mtime, original_mtime, rake_file)

      expect(before).not_to eq(after)
    end

    it 'detects changes to .erb view files' do
      before = described_class.compute(Rails.application)
      erb_file = Rails.root.join('app/views/posts/index.html.erb').to_s
      original_mtime = File.mtime(erb_file)

      FileUtils.touch(erb_file)
      after = described_class.compute(Rails.application)

      File.utime(original_mtime, original_mtime, erb_file)

      expect(before).not_to eq(after)
    end

    it 'detects changes to .js stimulus controllers' do
      controllers_dir = Rails.root.join('app/javascript/controllers').to_s
      FileUtils.mkdir_p(controllers_dir)
      js_file = File.join(controllers_dir, 'test_controller.js')
      File.write(js_file, '// test')

      before = described_class.compute(Rails.application)
      FileUtils.touch(js_file)
      after = described_class.compute(Rails.application)

      FileUtils.rm_rf(Rails.root.join('app/javascript').to_s)

      expect(before).not_to eq(after)
    end
  end

  describe '.changed?' do
    it 'returns false when fingerprint matches' do
      current = described_class.compute(Rails.application)
      expect(described_class.changed?(Rails.application, current)).to be false
    end

    it 'returns true when fingerprint differs' do
      expect(described_class.changed?(Rails.application, 'stale')).to be true
    end
  end
end

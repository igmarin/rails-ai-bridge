# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::PackDetector do
  describe '.detect_from_content' do
    context 'when Rails gem is present' do
      it 'detects Rails' do
        content = "source 'https://rubygems.org'\ngem 'rails', '~> 7.0'\n"
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Rails])
      end
    end

    context 'when Hanami gem is present' do
      it 'detects Hanami' do
        content = "source 'https://rubygems.org'\ngem \"hanami\", \"~> 2.0\"\n"
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Hanami])
      end
    end

    context 'when both Rails and Hanami are present' do
      it 'detects both frameworks' do
        content = "gem 'rails'\ngem 'hanami'"
        result = described_class.detect_from_content(content)
        expect(result).to eq([
                               RailsAiBridge::Registry::DetectedFramework::Rails,
                               RailsAiBridge::Registry::DetectedFramework::Hanami
                             ])
      end
    end

    context 'when no framework gems are present' do
      it 'returns empty array' do
        content = "gem 'rspec'\ngem 'rake'"
        result = described_class.detect_from_content(content)
        expect(result).to be_empty
      end
    end

    context 'when gems are commented out' do
      it 'ignores commented lines' do
        content = "# gem 'rails'\n#gem 'hanami'\ngem 'rails'"
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Rails])
      end
    end

    context 'with double quotes' do
      it 'detects Rails with double quotes' do
        content = 'gem "rails"'
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Rails])
      end

      it 'detects Hanami with double quotes' do
        content = 'gem "hanami"'
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Hanami])
      end
    end

    context 'with comma after gem name' do
      it 'detects Rails with comma' do
        content = "gem 'rails', '~> 7.0'"
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Rails])
      end

      it 'detects Hanami with comma' do
        content = 'gem "hanami", "~> 2.0"'
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Hanami])
      end
    end

    context 'with whitespace variations' do
      it 'detects Rails with extra spaces' do
        content = "  gem   'rails'  ,  '~> 7.0'  "
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Rails])
      end

      it 'handles tabs' do
        content = "\tgem\t'rails'\t"
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Rails])
      end
    end

    context 'with mixed quote styles' do
      it 'detects Rails with single quotes' do
        content = "gem 'rails'"
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Rails])
      end

      it 'detects Rails with double quotes' do
        content = 'gem "rails"'
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Rails])
      end
    end

    context 'with version constraints' do
      it 'detects Rails with version' do
        content = "gem 'rails', '~> 7.0'"
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Rails])
      end

      it 'detects Hanami with version' do
        content = 'gem "hanami", "~> 2.0"'
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Hanami])
      end
    end

    context 'edge cases' do
      it 'handles empty content' do
        result = described_class.detect_from_content('')
        expect(result).to be_empty
      end

      it 'handles content with only comments' do
        content = "# comment 1\n# comment 2"
        result = described_class.detect_from_content(content)
        expect(result).to be_empty
      end

      it 'handles case sensitivity' do
        content = "gem 'Rails'"
        result = described_class.detect_from_content(content)
        expect(result).to be_empty
      end

      it 'does not match partial names' do
        content = "gem 'rails_admin'"
        result = described_class.detect_from_content(content)
        expect(result).to be_empty
      end

      it 'does not match rails with version suffix' do
        content = "gem 'rails6'"
        result = described_class.detect_from_content(content)
        expect(result).to be_empty
      end

      it 'does not match hanami with prefix' do
        content = "gem 'hanami_utils'"
        result = described_class.detect_from_content(content)
        expect(result).to be_empty
      end

      it 'handles multiple rails declarations' do
        content = "gem 'rails'\ngem 'rails', '~> 6.0'"
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Rails])
      end

      it 'handles hanami with different quote styles in same file' do
        content = "gem 'hanami'\ngem \"hanami\""
        result = described_class.detect_from_content(content)
        expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Hanami])
      end
    end
  end

  describe '.detect_in_path' do
    context 'when Gemfile exists' do
      it 'reads and parses the Gemfile' do
        temp_dir = Dir.mktmpdir
        begin
          gemfile_path = File.join(temp_dir, 'Gemfile')
          File.write(gemfile_path, "gem 'rails'\n")

          result = described_class.detect_in_path(temp_dir)
          expect(result).to eq([RailsAiBridge::Registry::DetectedFramework::Rails])
        ensure
          FileUtils.rm_rf(temp_dir)
        end
      end

      it 'handles Gemfile with both frameworks' do
        temp_dir = Dir.mktmpdir
        begin
          gemfile_path = File.join(temp_dir, 'Gemfile')
          File.write(gemfile_path, "gem 'rails'\ngem 'hanami'\n")

          result = described_class.detect_in_path(temp_dir)
          expect(result).to eq([
                                 RailsAiBridge::Registry::DetectedFramework::Rails,
                                 RailsAiBridge::Registry::DetectedFramework::Hanami
                               ])
        ensure
          FileUtils.rm_rf(temp_dir)
        end
      end
    end

    context 'when Gemfile does not exist' do
      it 'returns empty array' do
        temp_dir = Dir.mktmpdir
        begin
          result = described_class.detect_in_path(temp_dir)
          expect(result).to be_empty
        ensure
          FileUtils.rm_rf(temp_dir)
        end
      end
    end

    context 'when path contains traversal' do
      it 'returns empty array for path with ..' do
        result = described_class.detect_in_path('/tmp/../etc')
        expect(result).to be_empty
      end
    end
  end

  describe '.detect' do
    it 'detects in current directory' do
      # This test would require setting up a Gemfile in the current directory
      # For now, we'll just verify the method calls detect_in_path with "."
      expect(described_class).to receive(:detect_in_path).with('.')
      described_class.detect
    end
  end
end

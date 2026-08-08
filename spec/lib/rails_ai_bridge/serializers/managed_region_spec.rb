# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Serializers::ManagedRegion do
  let(:payload) { "# Generated\n\nSome context.\n" }

  describe '.wrap' do
    it 'surrounds the payload with the begin and end markers' do
      wrapped = described_class.wrap(payload)

      expect(wrapped).to start_with("#{described_class::BEGIN_MARKER}\n")
      expect(wrapped).to end_with("#{described_class::END_MARKER}\n")
      expect(wrapped).to include('Some context.')
    end

    it 'is idempotent on payloads with or without a trailing newline' do
      expect(described_class.wrap(payload)).to eq(described_class.wrap(payload.chomp))
    end
  end

  describe '.markers?' do
    it 'is true for a complete region' do
      expect(described_class.markers?(described_class.wrap(payload))).to be true
    end

    it 'is false for unmarked content' do
      expect(described_class.markers?("just prose\n")).to be false
    end

    it 'is false for nil' do
      expect(described_class.markers?(nil)).to be false
    end

    it 'is true when the end marker is missing (region runs to end of file)' do
      expect(described_class.markers?("#{described_class::BEGIN_MARKER}\nbody\n")).to be true
    end
  end

  describe '.extract' do
    it 'returns the payload inside the markers' do
      expect(described_class.extract(described_class.wrap(payload))).to eq(payload.chomp)
    end

    it 'returns the payload when hand-authored content surrounds the region' do
      content = "Above.\n\n#{described_class.wrap(payload)}\nBelow.\n"

      expect(described_class.extract(content)).to eq(payload.chomp)
    end

    it 'returns nil for unmarked content' do
      expect(described_class.extract("just prose\n")).to be_nil
    end

    it 'returns nil for nil' do
      expect(described_class.extract(nil)).to be_nil
    end

    it 'recognises a region written with different marker wording' do
      content = "<!-- BEGIN rails-ai-bridge: generated -->\nbody\n<!-- END rails-ai-bridge -->\n"

      expect(described_class.extract(content)).to eq('body')
    end
  end

  describe '.generated_payload' do
    it 'returns the region when markers are present' do
      expect(described_class.generated_payload(described_class.wrap(payload))).to eq(payload.chomp)
    end

    it 'falls back to the whole content when unmarked' do
      expect(described_class.generated_payload('plain')).to eq('plain')
    end
  end

  describe '.merge' do
    it 'returns just the marked block when there is no existing file' do
      expect(described_class.merge(nil, payload)).to eq(described_class.wrap(payload))
    end

    it 'returns just the marked block when the existing file is blank' do
      expect(described_class.merge("\n  \n", payload)).to eq(described_class.wrap(payload))
    end

    it 'appends the block to an existing unmarked file, preserving it' do
      merged = described_class.merge("# House rules\n\nAlways use Sorbet.\n", payload)

      expect(merged).to start_with("# House rules\n\nAlways use Sorbet.\n\n")
      expect(merged).to include(described_class::BEGIN_MARKER)
      expect(described_class.extract(merged)).to eq(payload.chomp)
    end

    it 'replaces only the region, keeping content above and below' do
      existing = "Above.\n\n#{described_class.wrap('OLD')}\nBelow.\n"

      merged = described_class.merge(existing, payload)

      expect(merged).to start_with("Above.\n\n")
      expect(merged).to end_with("\nBelow.\n")
      expect(merged).not_to include('OLD')
      expect(described_class.extract(merged)).to eq(payload.chomp)
    end

    it 'is idempotent when the payload is unchanged' do
      once  = described_class.merge("Above.\n", payload)
      twice = described_class.merge(once, payload)

      expect(twice).to eq(once)
    end

    it 'does not interpret backslash sequences in the payload as regexp back-references' do
      merged = described_class.merge(described_class.wrap('OLD'), 'path \\1 and \\\\ and \0')

      expect(described_class.extract(merged)).to eq('path \\1 and \\\\ and \0')
    end

    it 'heals an unterminated region instead of nesting a second block inside it' do
      existing = "Above.\n\n#{described_class::BEGIN_MARKER}\ntruncated write\n"

      merged = described_class.merge(existing, payload)

      expect(merged).to start_with("Above.\n\n")
      expect(merged).not_to include('truncated write')
      expect(merged.scan(described_class::BEGIN_MARKER).size).to eq(1)
      expect(described_class.extract(merged)).to eq(payload.chomp)
    end

    it 'collapses trailing blank lines when appending to an existing file' do
      merged = described_class.merge("# House rules\n\n\n\n", payload)

      expect(merged).to start_with("# House rules\n\n#{described_class::BEGIN_MARKER}")
      expect(merged).not_to start_with("# House rules\n\n\n\n")
    end
  end
end

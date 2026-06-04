# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RailsAiBridge::Registry::FrontmatterParser do
  describe '.parse' do
    context 'with valid frontmatter' do
      subject(:metadata) { described_class.parse(content) }

      let(:content) do
        <<~MARKDOWN
          ---
          name: generate-api-collection
          version: 1.0.0
          description: Use when creating REST API endpoints.
          ---
          # Actual content down here...
        MARKDOWN
      end

      it 'parses name' do
        expect(metadata.name).to eq('generate-api-collection')
      end

      it 'parses version' do
        expect(metadata.version).to eq('1.0.0')
      end

      it 'parses description' do
        expect(metadata.description).to eq('Use when creating REST API endpoints.')
      end
    end

    context 'when frontmatter opening delimiter is missing' do
      it 'raises ParseError' do
        expect { described_class.parse("# No frontmatter here\n") }
          .to raise_error(RailsAiBridge::Registry::FrontmatterParser::ParseError, /opening delimiter/)
      end
    end

    context 'when frontmatter closing delimiter is missing' do
      it 'raises ParseError' do
        expect { described_class.parse("---\nname: foo\nversion: 1.0.0\n") }
          .to raise_error(RailsAiBridge::Registry::FrontmatterParser::ParseError, /closing delimiter/)
      end
    end

    context 'when frontmatter contains invalid YAML syntax' do
      it 'raises ParseError' do
        content = "---\nname: foo\n  bad: indent: [unclosed\n---\n"
        expect { described_class.parse(content) }
          .to raise_error(RailsAiBridge::Registry::FrontmatterParser::ParseError, /invalid yaml/i)
      end
    end

    context 'when frontmatter YAML is not a mapping' do
      it 'raises ParseError for a YAML sequence' do
        content = "---\n- item_one\n- item_two\n---\n"
        expect { described_class.parse(content) }
          .to raise_error(RailsAiBridge::Registry::FrontmatterParser::ParseError, /must be a yaml mapping/i)
      end

      it 'raises ParseError for a plain scalar' do
        content = "---\njust a string\n---\n"
        expect { described_class.parse(content) }
          .to raise_error(RailsAiBridge::Registry::FrontmatterParser::ParseError, /must be a yaml mapping/i)
      end
    end

    context 'when required fields are missing' do
      it 'raises ParseError for missing name' do
        content = "---\nversion: 1.0.0\ndescription: foo\n---\n"
        expect { described_class.parse(content) }
          .to raise_error(RailsAiBridge::Registry::FrontmatterParser::ParseError, /name/)
      end

      it 'raises ParseError for missing version' do
        content = "---\nname: foo\ndescription: bar\n---\n"
        expect { described_class.parse(content) }
          .to raise_error(RailsAiBridge::Registry::FrontmatterParser::ParseError, /version/)
      end

      it 'raises ParseError for missing description' do
        content = "---\nname: foo\nversion: 1.0.0\n---\n"
        expect { described_class.parse(content) }
          .to raise_error(RailsAiBridge::Registry::FrontmatterParser::ParseError, /description/)
      end
    end

    context 'with leading whitespace before the opening delimiter' do
      it 'still parses correctly' do
        content = "  ---\nname: foo\nversion: 1.0.0\ndescription: bar\n---\n"
        metadata = described_class.parse(content)
        expect(metadata.name).to eq('foo')
      end
    end

    context 'with content after the closing delimiter' do
      it 'ignores content after the closing delimiter' do
        content = "---\nname: foo\nversion: 1.0.0\ndescription: bar\n---\n# Body content ignored\n"
        metadata = described_class.parse(content)
        expect(metadata.name).to eq('foo')
      end
    end
  end
end

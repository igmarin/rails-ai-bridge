# frozen_string_literal: true

require 'spec_helper'
require 'rails_ai_bridge/serializers/formatters/sections/semantic_formatter'

RSpec.describe RailsAiBridge::Serializers::Formatters::Sections::SemanticFormatter do
  describe '#call' do
    it 'returns nil when data is empty' do
      formatter = described_class.new({ semantic: {} })
      expect(formatter.call).to be_nil
    end

    it 'returns nil when data contains info' do
      formatter = described_class.new({ semantic: { info: 'Not available' } })
      expect(formatter.call).to be_nil
    end

    it 'returns nil when data contains error' do
      formatter = described_class.new({ semantic: { error: 'Failed' } })
      expect(formatter.call).to be_nil
    end

    it 'renders semantic analysis properly' do
      data = {
        codebase_stats: {
          total_files: 10,
          total_declarations: 20,
          total_classes: 5,
          total_modules: 2,
          total_methods: 13,
          total_constant_references: 50,
          total_method_references: 100
        },
        patterns: {
          common_patterns: %w[Singleton Factory],
          namespace_distribution: { 'Admin' => 5, 'Api' => 10 }
        },
        relationships: {
          inheritance_tree: { 'ApplicationRecord' => %w[User Post] },
          most_extended: [{ name: 'BaseService', descendants_count: 8 }],
          orphan_classes: 3
        },
        complexity_hotspots: [
          { name: 'GodClass', type: 'class', complexity_score: 42, definitions_count: 10, ancestors_count: 2, descendants_count: 1 }
        ]
      }
      formatter = described_class.new({ semantic: data })
      result = formatter.call

      expect(result).to include('## Semantic Analysis (rubydex)')
      expect(result).to include('### Codebase Statistics')
      expect(result).to include('- Files indexed: 10')
      expect(result).to include('### Detected Patterns')
      expect(result).to include('- Common patterns: Singleton, Factory')
      expect(result).to include('- Namespace distribution:')
      expect(result).to include('- `Admin`: 5 declarations')
      expect(result).to include('### Code Relationships')
      expect(result).to include('- Inheritance tree (top parents):')
      expect(result).to include('- `ApplicationRecord` → User, Post')
      expect(result).to include('- Most extended classes:')
      expect(result).to include('- `BaseService` (8 descendants)')
      expect(result).to include('- Leaf classes (no descendants): 3')
      expect(result).to include('### Complexity Hotspots')
      expect(result).to include('- `GodClass` [class] — score: 42 (10 defs, 2 ancestors, 1 descendants)')
    end

    it 'handles empty or malformed sub-hashes gracefully' do
      data = {
        codebase_stats: [], # Invalid type
        patterns: { common_patterns: nil, namespace_distribution: [] },
        relationships: { inheritance_tree: nil, most_extended: nil, orphan_classes: -1 },
        complexity_hotspots: nil
      }
      formatter = described_class.new({ semantic: data })
      expect(formatter.call).to be_nil
    end
  end
end

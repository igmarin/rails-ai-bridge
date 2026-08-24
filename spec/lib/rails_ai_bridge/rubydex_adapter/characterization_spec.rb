# frozen_string_literal: true

require 'spec_helper'

# Characterization specs that pin the contract between RubydexAdapter and
# the Rubydex 0.3.0 graph API. When upgrading to Rubydex 0.4.0, these specs
# will surface any breaking changes in the graph, declaration, definition,
# location, or document object shapes.
#
# The 0.4.0 changelog notes these breaking changes:
#   - "Make Config a proper object" (#965) — may change Graph initialization
#   - "Return Cypher query results as graph objects" (#873) — may change
#     query return types
#   - "Extract declaration core" (#944) — may change declaration shape
#   - "Extract NamespaceStore" (#945) — may change namespace resolution
#
# These specs use mock doubles to isolate the adapter from the real Rubydex
# engine, pinning the *method names* and *return shapes* the adapter relies on.
RSpec.describe 'Rubydex 0.3 graph API contract' do
  let(:root) { '/tmp/test_root' }
  let(:adapter) { RailsAiBridge::RubydexAdapter.new(root) }

  before do
    stub_rubydex_module
  end

  after do
    RailsAiBridge::RubydexAdapter.reset!
    RailsAiBridge::RubydexAdapter.reset_availability!
  end

  # ---- Graph construction ----

  describe 'Rubydex::Graph initialization' do
    it 'constructs Graph with no arguments' do
      mock_graph = double('Graph')
      stub_rubydex_graph(mock_graph)

      adapter.index!

      expect(Rubydex::Graph).to have_received(:new).with(no_args)
    end
  end

  # ---- Indexing ----

  describe 'graph indexing methods' do
    it 'calls index_all with an array of file paths' do
      mock_graph = double('Graph')
      allow(mock_graph).to receive(:resolve)
      allow(mock_graph).to receive(:index_all)
      stub_rubydex_graph(mock_graph)

      adapter.index!

      expect(mock_graph).to have_received(:index_all).with(kind_of(Array))
    end

    it 'calls resolve with no arguments after indexing' do
      mock_graph = double('Graph')
      allow(mock_graph).to receive(:index_all)
      allow(mock_graph).to receive(:resolve)
      stub_rubydex_graph(mock_graph)

      adapter.index!

      expect(mock_graph).to have_received(:resolve).with(no_args)
    end
  end

  # ---- Search ----

  describe 'graph#search' do
    it 'calls search with a string query and maps results via serializer' do
      mock_graph = double('Graph')
      decl = double('Decl', name: 'User', class: double(name: 'Rubydex::ClassDeclaration'))
      allow(decl).to receive(:respond_to?).with(:unqualified_name).and_return(false)
      allow(mock_graph).to receive(:search).with('User').and_return([decl])
      index_adapter(adapter, mock_graph)

      results = adapter.search('User')

      expect(mock_graph).to have_received(:search).with('User')
      expect(results).to eq([{ name: 'User', type: 'class' }])
    end

    it 'limits results to max_results' do
      mock_graph = double('Graph')
      decls = Array.new(30) do |i|
        d = double("Decl#{i}", name: "Cls#{i}", class: double(name: 'Rubydex::ClassDeclaration'))
        allow(d).to receive(:respond_to?).with(:unqualified_name).and_return(false)
        d
      end
      allow(mock_graph).to receive(:search).with('Cls').and_return(decls)
      index_adapter(adapter, mock_graph)

      results = adapter.search('Cls', max_results: 5)

      expect(results.length).to eq(5)
    end
  end

  # ---- Declarations ----

  describe 'graph#[] for declaration lookup' do
    it 'retrieves a declaration by fully qualified name' do
      mock_graph = double('Graph')
      decl = double('Decl', name: 'Foo::Bar', class: double(name: 'Rubydex::ClassDeclaration'))
      allow(decl).to receive(:respond_to?).with(:unqualified_name).and_return(false)
      allow(decl).to receive(:respond_to?).with(:definitions).and_return(false)
      allow(decl).to receive(:respond_to?).with(:ancestors).and_return(false)
      allow(decl).to receive(:respond_to?).with(:descendants).and_return(false)
      allow(decl).to receive(:respond_to?).with(:owner).and_return(false)
      allow(mock_graph).to receive(:[]).with('Foo::Bar').and_return(decl)
      index_adapter(adapter, mock_graph)

      result = adapter.get_declaration('Foo::Bar')

      expect(mock_graph).to have_received(:[]).with('Foo::Bar')
      expect(result[:name]).to eq('Foo::Bar')
    end

    it 'returns nil when graph[] returns nil' do
      mock_graph = double('Graph')
      allow(mock_graph).to receive(:[]).with('Missing').and_return(nil)
      index_adapter(adapter, mock_graph)

      expect(adapter.get_declaration('Missing')).to be_nil
    end
  end

  describe 'graph#declarations' do
    it 'returns all declarations mapped through the serializer' do
      mock_graph = double('Graph')
      decl = double('Decl', name: 'User', class: double(name: 'Rubydex::ClassDeclaration'))
      allow(decl).to receive(:respond_to?).with(:unqualified_name).and_return(false)
      allow(mock_graph).to receive(:declarations).and_return([decl])
      index_adapter(adapter, mock_graph)

      results = adapter.all_declarations

      expect(mock_graph).to have_received(:declarations)
      expect(results).to eq([{ name: 'User', type: 'class' }])
    end
  end

  # ---- Definitions / file declarations ----

  describe 'graph#documents for file-scoped definitions' do
    it 'finds a document by uri suffix and maps its definitions' do
      mock_graph = double('Graph')
      defn = double('Defn', name: 'save', class: double(name: 'Rubydex::MethodDeclaration'))
      allow(defn).to receive(:respond_to?).with(:location).and_return(false)
      allow(defn).to receive(:respond_to?).with(:comments).and_return(false)
      allow(defn).to receive(:respond_to?).with(:deprecated?).and_return(false)
      doc = double('Doc', uri: '/tmp/test_root/app/models/user.rb', definitions: [defn])
      allow(mock_graph).to receive(:documents).and_return([doc])
      index_adapter(adapter, mock_graph)

      results = adapter.file_declarations('app/models/user.rb')

      expect(results).to eq([{ name: 'save' }])
    end

    it 'matches document by exact uri' do
      mock_graph = double('Graph')
      doc = double('Doc', uri: '/exact/path.rb', definitions: [])
      allow(mock_graph).to receive(:documents).and_return([doc])
      index_adapter(adapter, mock_graph)

      expect(adapter.file_declarations('/exact/path.rb')).to eq([])
      expect(mock_graph).to have_received(:documents)
    end
  end

  # ---- References ----

  describe 'graph#constant_references' do
    it 'maps constant references with name and location' do
      mock_graph = double('Graph')
      loc = double('Loc')
      allow(loc).to receive(:respond_to?).with(:path).and_return(false)
      allow(loc).to receive(:to_s).and_return('loc-string')
      ref = double('Ref', name: 'API_KEY', location: loc)
      allow(mock_graph).to receive(:constant_references).and_return([ref])
      index_adapter(adapter, mock_graph)

      results = adapter.constant_references

      expect(results).to eq([{ name: 'API_KEY', location: 'loc-string' }])
    end

    it 'handles references without a name method by falling back to to_s' do
      mock_graph = double('Graph')
      ref = double('Ref')
      allow(ref).to receive(:respond_to?).with(:name).and_return(false)
      allow(ref).to receive(:to_s).and_return('CONSTANT_REF')
      allow(ref).to receive(:respond_to?).with(:location).and_return(false)
      allow(mock_graph).to receive(:constant_references).and_return([ref])
      index_adapter(adapter, mock_graph)

      results = adapter.constant_references

      expect(results.first[:name]).to eq('CONSTANT_REF')
    end
  end

  # ---- Locations ----

  describe 'location object contract' do
    it 'relativizes a location path against root' do
      loc = double('Loc')
      allow(loc).to receive(:respond_to?).with(:path).and_return(true)
      allow(loc).to receive(:path).and_return('/tmp/test_root/app/models/user.rb')

      result = RailsAiBridge::RubydexAdapter::Serializer.format_location(loc, root)

      expect(result).to eq('app/models/user.rb')
    end

    it 'returns to_s when location has no path method' do
      loc = double('Loc', to_s: 'raw-location')
      allow(loc).to receive(:respond_to?).with(:path).and_return(false)

      result = RailsAiBridge::RubydexAdapter::Serializer.format_location(loc, root)

      expect(result).to eq('raw-location')
    end

    it 'returns to_s when location path is nil' do
      loc = double('Loc', to_s: 'fallback-string')
      allow(loc).to receive(:respond_to?).with(:path).and_return(true)
      allow(loc).to receive(:path).and_return(nil)

      result = RailsAiBridge::RubydexAdapter::Serializer.format_location(loc, root)

      expect(result).to eq('fallback-string')
    end
  end

  # ---- Ancestors / Descendants ----

  describe 'declaration#ancestors' do
    it 'maps ancestor names from declaration objects' do
      mock_graph = double('Graph')
      parent = double('Parent', name: 'ApplicationRecord')
      decl = double('Decl', ancestors: [parent])
      allow(decl).to receive(:respond_to?).with(:ancestors).and_return(true)
      allow(mock_graph).to receive(:[]).with('User').and_return(decl)
      index_adapter(adapter, mock_graph)

      expect(adapter.ancestors('User')).to eq(['ApplicationRecord'])
    end

    it 'returns empty array when declaration does not respond to ancestors' do
      mock_graph = double('Graph')
      decl = double('Decl')
      allow(decl).to receive(:respond_to?).with(:ancestors).and_return(false)
      allow(mock_graph).to receive(:[]).with('User').and_return(decl)
      index_adapter(adapter, mock_graph)

      expect(adapter.ancestors('User')).to eq([])
    end
  end

  describe 'declaration#descendants' do
    it 'maps descendant names from declaration objects' do
      mock_graph = double('Graph')
      child = double('Child', name: 'Admin')
      decl = double('Decl', descendants: [child])
      allow(decl).to receive(:respond_to?).with(:descendants).and_return(true)
      allow(mock_graph).to receive(:[]).with('User').and_return(decl)
      index_adapter(adapter, mock_graph)

      expect(adapter.descendants('User')).to eq(['Admin'])
    end

    it 'returns empty array when declaration does not respond to descendants' do
      mock_graph = double('Graph')
      decl = double('Decl')
      allow(decl).to receive(:respond_to?).with(:descendants).and_return(false)
      allow(mock_graph).to receive(:[]).with('User').and_return(decl)
      index_adapter(adapter, mock_graph)

      expect(adapter.descendants('User')).to eq([])
    end
  end

  # ---- Declaration type detection ----

  describe 'declaration type detection via class name' do
    it 'detects class from Rubydex::ClassDeclaration' do
      decl = double('Decl', class: double(name: 'Rubydex::ClassDeclaration'))
      expect(RailsAiBridge::RubydexAdapter::Serializer.declaration_type(decl)).to eq('class')
    end

    it 'detects module from Rubydex::ModuleDeclaration' do
      decl = double('Decl', class: double(name: 'Rubydex::ModuleDeclaration'))
      expect(RailsAiBridge::RubydexAdapter::Serializer.declaration_type(decl)).to eq('module')
    end

    it 'detects method from Rubydex::MethodDeclaration' do
      decl = double('Decl', class: double(name: 'Rubydex::MethodDeclaration'))
      expect(RailsAiBridge::RubydexAdapter::Serializer.declaration_type(decl)).to eq('method')
    end

    it 'detects constant from Rubydex::ConstantDeclaration' do
      decl = double('Decl', class: double(name: 'Rubydex::ConstantDeclaration'))
      expect(RailsAiBridge::RubydexAdapter::Serializer.declaration_type(decl)).to eq('constant')
    end

    it 'falls back to declaration for unknown types' do
      decl = double('Decl', class: double(name: 'Rubydex::UnknownType'))
      expect(RailsAiBridge::RubydexAdapter::Serializer.declaration_type(decl)).to eq('declaration')
    end
  end

  # ---- Codebase stats ----

  describe 'codebase_stats graph method surface' do
    it 'calls declarations, documents, constant_references, and method_references' do
      mock_graph = double('Graph')
      mock_counter = instance_double(RailsAiBridge::RubydexAdapter::MethodCounter)
      allow(mock_counter).to receive(:count).and_return(10)
      allow(mock_graph).to receive_messages(
        declarations: [],
        documents: [],
        constant_references: [],
        method_references: []
      )
      index_adapter(adapter, mock_graph)
      adapter.instance_variable_set(:@method_counter, mock_counter)

      stats = adapter.codebase_stats

      expect(mock_graph).to have_received(:declarations)
      expect(mock_graph).to have_received(:documents)
      expect(mock_graph).to have_received(:constant_references)
      expect(mock_graph).to have_received(:method_references)
      expect(stats).to include(
        total_files: 0,
        total_declarations: 0,
        total_classes: 0,
        total_modules: 0,
        total_methods: 10,
        total_constant_references: 0,
        total_method_references: 0
      )
    end

    it 'returns 0 for method_references when graph does not respond to it' do
      mock_graph = double('Graph')
      mock_counter = instance_double(RailsAiBridge::RubydexAdapter::MethodCounter)
      allow(mock_counter).to receive(:count).and_return(0)
      allow(mock_graph).to receive_messages(declarations: [], documents: [])
      allow(mock_graph).to receive_messages(constant_references: [], respond_to?: true)
      allow(mock_graph).to receive(:respond_to?).with(:method_references).and_return(false)
      index_adapter(adapter, mock_graph)
      adapter.instance_variable_set(:@method_counter, mock_counter)

      stats = adapter.codebase_stats

      expect(stats[:total_method_references]).to eq(0)
    end
  end

  # ---- Graceful failure ----

  describe 'graceful failure when not indexed' do
    before do
      allow(RailsAiBridge::RubydexAdapter).to receive(:available?).and_return(false)
    end

    it 'returns empty array for search' do
      expect(adapter.search('User')).to eq([])
    end

    it 'returns nil for get_declaration' do
      expect(adapter.get_declaration('User')).to be_nil
    end

    it 'returns empty array for all_declarations' do
      expect(adapter.all_declarations).to eq([])
    end

    it 'returns empty array for file_declarations' do
      expect(adapter.file_declarations('app/models/user.rb')).to eq([])
    end

    it 'returns empty array for descendants' do
      expect(adapter.descendants('User')).to eq([])
    end

    it 'returns empty array for ancestors' do
      expect(adapter.ancestors('User')).to eq([])
    end

    it 'returns empty array for constant_references' do
      expect(adapter.constant_references).to eq([])
    end

    it 'returns empty hash for codebase_stats' do
      expect(adapter.codebase_stats).to eq({})
    end
  end

  describe 'graceful failure when graph raises' do
    it 'returns empty array when search raises' do
      mock_graph = double('Graph')
      allow(mock_graph).to receive(:search).and_raise(StandardError, 'boom')
      index_adapter(adapter, mock_graph)

      expect(adapter.search('User')).to eq([])
    end

    it 'returns nil when get_declaration raises' do
      mock_graph = double('Graph')
      allow(mock_graph).to receive(:[]).and_raise(StandardError, 'boom')
      index_adapter(adapter, mock_graph)

      expect(adapter.get_declaration('User')).to be_nil
    end

    it 'returns empty array when all_declarations raises' do
      mock_graph = double('Graph')
      allow(mock_graph).to receive(:declarations).and_raise(StandardError, 'boom')
      index_adapter(adapter, mock_graph)

      expect(adapter.all_declarations).to eq([])
    end

    it 'returns empty hash when codebase_stats raises' do
      mock_graph = double('Graph')
      allow(mock_graph).to receive(:declarations).and_raise(StandardError, 'boom')
      index_adapter(adapter, mock_graph)

      expect(adapter.codebase_stats).to eq({})
    end
  end

  # ---- Helpers ----

  private

  def stub_rubydex_module
    return if defined?(Rubydex)

    Object.const_set(:Rubydex, Module.new)
    Rubydex.const_set(:Graph, Class.new)
  end

  def stub_rubydex_graph(mock_graph)
    allow(RailsAiBridge::RubydexAdapter).to receive(:available?).and_return(true)
    allow(mock_graph).to receive(:empty?).and_return(false)
    allow(mock_graph).to receive(:index_all)
    allow(mock_graph).to receive(:resolve)
    allow(Rubydex::Graph).to receive(:new).and_return(mock_graph)
    allow(RailsAiBridge::RubydexAdapter::Indexer).to receive(:source_files).and_return([])
    allow(adapter).to receive(:sanitize_index_path).and_return(nil)
  end

  def index_adapter(adapter, mock_graph)
    allow(mock_graph).to receive(:empty?).and_return(false)
    adapter.instance_variable_set(:@indexed, true)
    adapter.instance_variable_set(:@graph, mock_graph)
  end
end

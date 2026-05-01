# frozen_string_literal: true

require 'pathname'

# Builds serializer-ready contexts from Rails-shaped fixture directories.
#
# :reek:NestedIterators
# :reek:TooManyStatements
module RealFixtureAppContext
  module_function

  # Builds a serializer-ready context from a Rails-shaped fixture app.
  #
  # @param profile [Symbol, String] fixture directory name under +spec/fixtures/apps+
  # @return [Hash] context hash shaped like {RailsAiBridge::Introspector#call}
  def build(profile)
    root = Pathname.new(File.expand_path("../fixtures/apps/#{profile}", __dir__))
    app = Struct.new(:root).new(root)

    {
      app_name: profile.to_s.camelize,
      rails_version: '8.0.0',
      ruby_version: RUBY_VERSION,
      generated_at: Time.now.iso8601,
      environment: 'test',
      schema: schema_for(root),
      models: models_for(root),
      routes: routes_for(root),
      controllers: controllers_for(root),
      views: RailsAiBridge::Introspectors::ViewIntrospector.new(app).call,
      stimulus: RailsAiBridge::Introspectors::StimulusIntrospector.new(app).call,
      gems: { notable_gems: [] },
      conventions: { architecture: ['mvc'], patterns: ['service_objects'] },
      tests: { framework: 'rspec' }
    }
  end

  # Parses the fixture app's static schema file.
  #
  # @param root [Pathname] fixture app root
  # @return [Hash] parsed schema payload or an error hash when absent
  def schema_for(root)
    path = root.join('db/schema.rb')
    return { error: "No schema.rb found at #{path}" } unless path.file?

    RailsAiBridge::Introspectors::Schema::StaticSchemaParser
      .new(content: path.read, config: RailsAiBridge.configuration)
      .call
  end

  # Extracts lightweight model metadata from fixture model source files.
  #
  # @param root [Pathname] fixture app root
  # @return [Hash{String => Hash}] model metadata keyed by class name
  def models_for(root)
    Dir.glob(root.join('app/models/**/*.rb')).each_with_object({}) do |path, models|
      next if path.include?('/concerns/')

      content = File.read(path)
      class_name = content[/^\s*class\s+([A-Z][\w:]+)/, 1]
      next unless class_name

      models[class_name] = {
        table_name: class_name.demodulize.underscore.pluralize,
        semantic_tier: semantic_tier_for(content),
        associations: associations_for(content),
        validations: validations_for(content),
        scopes: content.scan(/^\s*scope\s+:(\w+)/).flatten,
        callbacks: {},
        enums: {}
      }
    end
  end

  # Extracts route metadata from the fixture app's route file.
  #
  # @param root [Pathname] fixture app root
  # @return [Hash] route payload grouped by controller
  def routes_for(root)
    route_file = RouteFile.new(root.join('config/routes.rb'))
    route_rows = route_file.routes

    {
      total_routes: route_rows.size,
      by_controller: route_rows.group_by { |route| route[:controller] }
                               .transform_values { |routes| routes.map { |route| route.except(:controller) } },
      api_namespaces: route_rows.filter_map { |route| route[:path][%r{\A/api/v?\d*}] }.uniq,
      mounted_engines: route_file.mounted_engines
    }
  end

  # Extracts lightweight controller metadata from fixture controller source files.
  #
  # @param root [Pathname] fixture app root
  # @return [Hash] controller payload keyed under +:controllers+
  def controllers_for(root)
    controllers = Dir.glob(root.join('app/controllers/**/*.rb')).each_with_object({}) do |path, data|
      content = File.read(path)
      class_name = content[/^\s*class\s+([A-Z][\w:]+)/, 1]
      next unless class_name && class_name != 'ApplicationController'

      data[class_name] = {
        parent_class: content[/^\s*class\s+[A-Z][\w:]+\s+<\s+([A-Z][\w:]*)/, 1],
        api_controller: content.include?('ActionController::API'),
        actions: content.scan(/^\s*def\s+(\w+)/).flatten.reject { |name| name.end_with?('_params') },
        filters: [],
        concerns: [],
        strong_params: content.scan(/^\s*def\s+(\w+_params)/).flatten,
        respond_to_formats: []
      }
    end

    { controllers: controllers }
  end

  # Classifies fixture models using a source-file marker.
  #
  # @param content [String] model source
  # @return [String] semantic tier label
  def semantic_tier_for(content)
    content.include?('# rails-ai-bridge: core') ? 'core_entity' : 'supporting'
  end

  # Extracts association macro metadata from model source.
  #
  # @param content [String] model source
  # @return [Array<Hash>] association descriptors
  def associations_for(content)
    content.scan(/^\s*(has_many|has_one|belongs_to|has_and_belongs_to_many)\s+:([a-z_]+)/).map do |type, name|
      { type: type, name: name }
    end
  end

  # Extracts validation metadata from model source.
  #
  # @param content [String] model source
  # @return [Array<Hash>] validation descriptors
  def validations_for(content)
    content.scan(/^\s*validates\s+(.+?),\s+/).flatten.flat_map do |attribute_list|
      attribute_list.scan(/:(\w+)/).flatten.map { |attribute| { kind: 'presence', attributes: [attribute] } }
    end
  end

  # Minimal parser for the small subset of Rails routing DSL used by fixture apps.
  #
  # :reek:ControlParameter
  # :reek:FeatureEnvy
  # :reek:TooManyStatements
  # :reek:UtilityFunction
  class RouteFile
    RESOURCE_ACTIONS = {
      index: 'GET',
      show: 'GET',
      new: 'GET',
      edit: 'GET',
      create: 'POST',
      update: 'PATCH',
      destroy: 'DELETE'
    }.freeze

    # @return [Array<Hash>] parsed route rows
    attr_reader :routes

    # @return [Array<Hash>] mounted engine descriptors
    attr_reader :mounted_engines

    def initialize(path)
      @path = path
      @namespaces = []
      @routes = []
      @mounted_engines = []
      parse_file if @path.file?
    end

    private

    def parse_file
      @path.each_line { |line| parse_line(line.strip) }
    end

    def parse_line(line)
      return if line.empty? || line.start_with?('#')

      if (namespace = line[/\Anamespace\s+:([a-z0-9_]+)/, 1])
        @namespaces << namespace
      elsif (engine = line.match(/\Amount\s+([A-Z][\w:]+)\s+=>\s+["']([^"']+)["']/))
        add_mounted_engine(engine[1], engine[2])
      elsif line == 'end'
        @namespaces.pop
      elsif (resource = line[/\Aresources\s+:([a-z_]+)/, 1])
        add_resource_routes(resource, only_actions(line))
      elsif (target = line[/\Aroot\s+["']([^"']+)["']/, 1])
        add_route('GET', '/', target)
      elsif (verb = line[/\A(get|post|patch|put|delete)\s+/, 1])
        add_direct_route(verb.upcase, line)
      end
    end

    def add_resource_routes(resource, actions)
      controller = namespaced(resource)
      actions.each do |action|
        @routes << {
          verb: RESOURCE_ACTIONS.fetch(action),
          path: resource_path(resource, action),
          controller: controller,
          action: action.to_s
        }
      end
    end

    def add_direct_route(verb, line)
      path = line[/\A\w+\s+["']([^"']+)["']/, 1]
      target = line[/to:\s+["']([^"']+)["']/, 1]
      add_route(verb, "/#{path}", target) if path && target
    end

    def add_mounted_engine(engine, path)
      @mounted_engines << { engine: engine, path: path }
    end

    def add_route(verb, path, target)
      controller, action = target.split('#', 2)
      @routes << { verb: verb, path: path, controller: namespaced(controller), action: action }
    end

    def only_actions(line)
      action_list = line[/only:\s+%i\[([^\]]+)\]/, 1]
      return RESOURCE_ACTIONS.keys unless action_list

      action_list.split.map(&:to_sym)
    end

    def resource_path(resource, action)
      base = "/#{(@namespaces + [resource]).join('/')}"
      case action
      when :show, :edit, :update, :destroy then "#{base}/:id"
      when :new then "#{base}/new"
      else base
      end
    end

    def namespaced(name)
      (@namespaces + [name]).join('/')
    end
  end
end

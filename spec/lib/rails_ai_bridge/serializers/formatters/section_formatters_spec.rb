# frozen_string_literal: true

require "spec_helper"

# Characterization tests for section formatters. Each formatter must:
# 1. Return nil when the context key is absent
# 2. Return nil when data has an error
# 3. Return a Markdown string with the expected heading when data is present
module RailsAiBridge
  module Serializers
    module Formatters
      RSpec.describe "Section formatters" do
        def render(klass, ctx)
          klass.new(ctx).call
        end

        # -------------------------------------------------------------------
        # SchemaFormatter
        # -------------------------------------------------------------------
        describe SchemaFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { schema: { error: "x" } })).to be_nil }

          it "renders schema heading with table count" do
            ctx = { schema: { total_tables: 2, tables: { "users" => { columns: [ { name: "id", type: "integer" } ] } } } }
            expect(render(described_class, ctx)).to include("Database Schema")
          end
        end

        # -------------------------------------------------------------------
        # RoutesFormatter
        # -------------------------------------------------------------------
        describe RoutesFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { routes: { error: "x" } })).to be_nil }

          it "renders routes heading" do
            ctx = { routes: { total_routes: 1, by_controller: { "Users" => [ { verb: "GET", path: "/users", action: "index" } ] } } }
            expect(render(described_class, ctx)).to include("Routes")
          end
        end

        # -------------------------------------------------------------------
        # ModelsFormatter
        # -------------------------------------------------------------------
        describe ModelsFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { models: { error: "x" } })).to be_nil }

          it "renders models heading with count" do
            ctx = { models: { "User" => { table_name: "users", associations: [], validations: [], enums: {} } } }
            expect(render(described_class, ctx)).to include("Models (1)")
          end
        end

        # -------------------------------------------------------------------
        # GemsFormatter
        # -------------------------------------------------------------------
        describe GemsFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { gems: { error: "x" } })).to be_nil }

          it "renders notable gems" do
            ctx = { gems: { notable_gems: [ { category: "auth", name: "devise", version: "4.8", note: "Auth" } ] } }
            expect(render(described_class, ctx)).to include("Notable Gems")
          end
        end

        # -------------------------------------------------------------------
        # ConventionsFormatter
        # -------------------------------------------------------------------
        describe ConventionsFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { conventions: { error: "x" } })).to be_nil }

          it "renders project structure" do
            ctx = { conventions: { directory_structure: { "app" => 5 } } }
            expect(render(described_class, ctx)).to include("Project Structure")
          end
        end

        # -------------------------------------------------------------------
        # JobsFormatter
        # -------------------------------------------------------------------
        describe JobsFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { jobs: { error: "x" } })).to be_nil }

          it "renders jobs section" do
            ctx = { jobs: { jobs: [ { name: "SendEmailJob", queue: "default" } ], mailers: [], channels: [] } }
            expect(render(described_class, ctx)).to include("Background Jobs")
          end

          it "returns nil when all sections are empty" do
            ctx = { jobs: { jobs: [], mailers: [], channels: [] } }
            expect(render(described_class, ctx)).to be_nil
          end
        end

        # -------------------------------------------------------------------
        # I18nFormatter
        # -------------------------------------------------------------------
        describe I18nFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { i18n: { error: "x" } })).to be_nil }

          it "renders i18n heading" do
            ctx = { i18n: { default_locale: "en", available_locales: [ "en" ], total_locale_files: 1 } }
            expect(render(described_class, ctx)).to include("Internationalization")
          end
        end

        # -------------------------------------------------------------------
        # ConfigFormatter
        # -------------------------------------------------------------------
        describe ConfigFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { config: { error: "x" } })).to be_nil }

          it "renders configuration heading" do
            ctx = { config: { cache_store: "memory_store", session_store: "cookie_store" } }
            expect(render(described_class, ctx)).to include("Configuration")
          end
        end

        # -------------------------------------------------------------------
        # ActiveStorageFormatter
        # -------------------------------------------------------------------
        describe ActiveStorageFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { active_storage: { error: "x" } })).to be_nil }

          it("returns nil when no attachments") { expect(render(described_class, { active_storage: { attachments: [] } })).to be_nil }

          it "renders active storage heading" do
            ctx = { active_storage: { attachments: [ { model: "User", type: "has_one_attached", name: "avatar" } ] } }
            expect(render(described_class, ctx)).to include("Active Storage")
          end
        end

        # -------------------------------------------------------------------
        # ActionTextFormatter
        # -------------------------------------------------------------------
        describe ActionTextFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { action_text: { error: "x" } })).to be_nil }

          it("returns nil when no fields") { expect(render(described_class, { action_text: { rich_text_fields: [] } })).to be_nil }

          it "renders action text heading" do
            ctx = { action_text: { rich_text_fields: [ { model: "Post", field: "body" } ] } }
            expect(render(described_class, ctx)).to include("Action Text")
          end
        end

        # -------------------------------------------------------------------
        # AssetsFormatter
        # -------------------------------------------------------------------
        describe AssetsFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { assets: { error: "x" } })).to be_nil }

          it "renders asset pipeline heading" do
            ctx = { assets: { pipeline: "sprockets", js_bundler: "esbuild" } }
            expect(render(described_class, ctx)).to include("Asset Pipeline")
          end
        end

        # -------------------------------------------------------------------
        # DevopsFormatter
        # -------------------------------------------------------------------
        describe DevopsFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { devops: { error: "x" } })).to be_nil }

          it "renders devops heading" do
            ctx = { devops: { puma: { threads_min: 0, threads_max: 16, workers: 2 } } }
            expect(render(described_class, ctx)).to include("DevOps")
          end
        end

        # -------------------------------------------------------------------
        # ActionMailboxFormatter
        # -------------------------------------------------------------------
        describe ActionMailboxFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { action_mailbox: { error: "x" } })).to be_nil }

          it("returns nil when no mailboxes") { expect(render(described_class, { action_mailbox: { mailboxes: [] } })).to be_nil }

          it "renders action mailbox heading" do
            ctx = { action_mailbox: { mailboxes: [ { name: "ForwardsMailbox" } ] } }
            expect(render(described_class, ctx)).to include("Action Mailbox")
          end
        end

        # -------------------------------------------------------------------
        # MigrationsFormatter
        # -------------------------------------------------------------------
        describe MigrationsFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { migrations: { error: "x" } })).to be_nil }

          it "renders migrations heading" do
            ctx = { migrations: { total: 5, schema_version: "20230101000000", pending: [], recent: [] } }
            expect(render(described_class, ctx)).to include("Migrations")
          end
        end

        # -------------------------------------------------------------------
        # SeedsFormatter
        # -------------------------------------------------------------------
        describe SeedsFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { seeds: { error: "x" } })).to be_nil }

          it "renders seeds heading" do
            ctx = { seeds: { seeds_file: { exists: true }, models_seeded: [ "User" ], seed_files: [] } }
            expect(render(described_class, ctx)).to include("Database Seeds")
          end
        end

        # -------------------------------------------------------------------
        # MiddlewareFormatter
        # -------------------------------------------------------------------
        describe MiddlewareFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { middleware: { error: "x" } })).to be_nil }

          it "renders middleware heading" do
            ctx = { middleware: { custom_middleware: [ { class_name: "ApiMiddleware", file: "api.rb", detected_patterns: [] } ] } }
            expect(render(described_class, ctx)).to include("Custom Middleware")
          end
        end

        # -------------------------------------------------------------------
        # EnginesFormatter
        # -------------------------------------------------------------------
        describe EnginesFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { engines: { error: "x" } })).to be_nil }

          it "renders engines heading" do
            ctx = { engines: { mounted_engines: [ { engine: "APIEngine", path: "/api" } ] } }
            expect(render(described_class, ctx)).to include("Mounted Engines")
          end
        end

        # -------------------------------------------------------------------
        # RakeTasksFormatter
        # -------------------------------------------------------------------
        describe RakeTasksFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { rake_tasks: { error: "x" } })).to be_nil }

          it("returns nil when no tasks") { expect(render(described_class, { rake_tasks: { tasks: [] } })).to be_nil }

          it "renders rake tasks heading" do
            ctx = { rake_tasks: { tasks: [ { name: "db:migrate", description: "Run migrations" } ] } }
            expect(render(described_class, ctx)).to include("Rake Tasks")
          end
        end

        # -------------------------------------------------------------------
        # TestsFormatter
        # -------------------------------------------------------------------
        describe TestsFormatter do
          it("returns nil when absent") { expect(render(described_class, {})).to be_nil }
          it("returns nil on error")    { expect(render(described_class, { tests: { error: "x" } })).to be_nil }

          it "renders testing heading" do
            ctx = { tests: { framework: "RSpec", factories: nil, fixtures: nil, system_tests: nil, ci_config: [], coverage: nil } }
            expect(render(described_class, ctx)).to include("Testing")
          end
        end

        # -------------------------------------------------------------------
        # AppOverviewFormatter
        # -------------------------------------------------------------------
        describe AppOverviewFormatter do
          it "renders overview heading" do
            ctx = { conventions: { architecture: [ "MVC" ], patterns: [ "Service Objects" ] } }
            expect(render(described_class, ctx)).to include("Overview")
          end

          it "handles missing conventions gracefully" do
            expect(render(described_class, {})).to include("Overview")
          end
        end
      end
    end
  end
end

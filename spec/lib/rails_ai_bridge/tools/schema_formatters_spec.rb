# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RailsAiBridge::Tools::Schema formatters" do
  let(:tables) do
    {
      "users" => {
        columns: [
          { name: "id", type: "integer", null: false, default: nil },
          { name: "email", type: "string", null: false, default: nil }
        ],
        indexes: [ { name: "index_users_on_email", columns: [ "email" ], unique: true } ],
        foreign_keys: []
      },
      "posts" => {
        columns: [
          { name: "id", type: "integer", null: false, default: nil },
          { name: "user_id", type: "integer", null: false, default: nil },
          { name: "title", type: "string", null: true, default: nil }
        ],
        indexes: [ { name: "index_posts_on_user_id", columns: [ "user_id" ], unique: false } ],
        foreign_keys: [ { column: "user_id", to_table: "users", primary_key: "id" } ]
      }
    }
  end

  describe RailsAiBridge::Tools::Schema::SummaryFormatter do
    subject(:output) { described_class.new(tables: tables, total: 2, limit: 50, offset: 0).call }

    it "includes the total table count in the header" do
      expect(output).to include("Schema Summary (2 tables)")
    end

    it "lists each table with column and index counts" do
      expect(output).to include("**users** — 2 columns, 1 indexes")
      expect(output).to include("**posts** — 3 columns, 1 indexes")
    end

    it "does not include column names or types" do
      expect(output).not_to include("id:integer")
      expect(output).not_to include("| Column |")
    end

    it "includes a pagination hint when more tables exist" do
      output = described_class.new(tables: tables, total: 10, limit: 2, offset: 0).call
      expect(output).to include("offset:2")
    end

    it "omits pagination hint when all tables are shown" do
      expect(output).not_to include("offset:")
    end
  end

  describe RailsAiBridge::Tools::Schema::StandardFormatter do
    subject(:output) { described_class.new(tables: tables, total: 2, limit: 15, offset: 0).call }

    it "includes the table count in the header" do
      expect(output).to include("showing 2")
    end

    it "lists column names and types" do
      expect(output).to include("id:integer")
      expect(output).to include("email:string")
    end

    it "does not include index details" do
      expect(output).not_to include("Indexes")
    end

    it "includes navigation hint when more tables exist" do
      output = described_class.new(tables: tables, total: 10, limit: 2, offset: 0).call
      expect(output).to include("detail:\"summary\"")
    end
  end

  describe RailsAiBridge::Tools::Schema::FullFormatter do
    subject(:output) { described_class.new(tables: tables, total: 2, limit: 5, offset: 0).call }

    it "includes 'Full Detail' in the header" do
      expect(output).to include("Full Detail")
    end

    it "renders a column table for each table" do
      expect(output).to include("| Column |")
    end

    it "includes index details" do
      expect(output).to include("Indexes")
      expect(output).to include("index_users_on_email")
    end

    it "includes foreign key details" do
      expect(output).to include("Foreign keys")
      expect(output).to include("users.id")
    end

    it "includes pagination hint when more tables exist" do
      output = described_class.new(tables: tables, total: 10, limit: 2, offset: 0).call
      expect(output).to include("offset:2")
    end
  end

  describe RailsAiBridge::Tools::Schema::TableFormatter do
    subject(:output) { described_class.new(name: "users", data: tables["users"]).call }

    it "renders a table header" do
      expect(output).to include("## Table: users")
    end

    it "renders each column as a markdown table row" do
      expect(output).to include("| email | string | no | - |")
    end

    it "renders index details" do
      expect(output).to include("index_users_on_email")
      expect(output).to include("(unique)")
    end

    it "does not render Foreign keys section when there are none" do
      expect(output).not_to include("Foreign keys")
    end

    it "renders foreign keys when present" do
      output = described_class.new(name: "posts", data: tables["posts"]).call
      expect(output).to include("Foreign keys")
      expect(output).to include("`user_id` → `users.id`")
    end
  end
end

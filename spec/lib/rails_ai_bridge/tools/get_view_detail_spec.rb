# frozen_string_literal: true

require "pathname"
require "spec_helper"

RSpec.describe RailsAiBridge::Tools::GetView do
  before { described_class.reset_cache! }

  describe "detail parameter" do
    before do
      allow(described_class).to receive(:cached_section).with(:views).and_return({
        layouts: [ "application.html.erb" ],
        template_engines: [ "erb" ],
        templates: {
          "admin/reports" => [ "index.html.erb" ],
          "users" => [ "index.html.erb", "show.html.erb" ]
        },
        partials: {
          shared: [ "_flash.html.erb" ],
          per_controller: {
            "users" => [ "_form.html.erb" ]
          }
        },
        helpers: [
          { file: "users_helper.rb", methods: %w[display_name status_badge] }
        ],
        view_components: [ "button_component" ]
      })
    end

    it "returns controller-level counts for detail:summary" do
      result = described_class.call(detail: "summary")
      text = result.content.first[:text]

      expect(text).to include("View Summary")
      expect(text).to include("**users/**")
      expect(text).to include("2 templates")
      expect(text).to include("1 partials")
    end

    it "returns template listings for detail:standard" do
      result = described_class.call(detail: "standard")
      text = result.content.first[:text]

      expect(text).to include("Layouts: application.html.erb")
      expect(text).to include("`users/`")
      expect(text).to include("index.html.erb, show.html.erb")
      expect(text).to include("_flash.html.erb")
    end

    it "returns helper methods and components for detail:full" do
      result = described_class.call(detail: "full")
      text = result.content.first[:text]

      expect(text).to include("## Helpers")
      expect(text).to include("display_name")
      expect(text).to include("## View Components")
      expect(text).to include("button_component")
    end

    it "filters by controller" do
      result = described_class.call(controller: "users")
      text = result.content.first[:text]

      expect(text).to include("users/")
      expect(text).to include("_form.html.erb")
      expect(text).not_to include("admin/reports")
    end

    it "returns full detail for a specific path" do
      Dir.mktmpdir do |dir|
        views_dir = File.join(dir, "app/views/users")
        FileUtils.mkdir_p(views_dir)
        File.write(
          File.join(views_dir, "index.html.erb"),
          <<~ERB
            <%= render "form" %>
            <div data-controller="clipboard modal" data-action="click->clipboard#copy">
              <%= turbo_frame_tag "user_form" do %>
                <%= render partial: "shared/flash" %>
              <% end %>
            </div>
          ERB
        )

        allow(described_class).to receive(:rails_app).and_return(double(root: Pathname.new(dir)))

        result = described_class.call(path: "users/index.html.erb")
        text = result.content.first[:text]

        expect(text).to include("# View: users/index.html.erb")
        expect(text).to include("clipboard")
        expect(text).to include("modal")
        expect(text).to include("user_form")
        expect(text).to include("shared/flash")
      end
    end

    it "rejects paths outside app/views" do
      Dir.mktmpdir do |dir|
        allow(described_class).to receive(:rails_app).and_return(double(root: Pathname.new(dir)))

        result = described_class.call(path: "../secrets.yml")
        text = result.content.first[:text]

        expect(text).to match(/Path not (found|allowed)/)
      end
    end

    it "handles missing views gracefully" do
      allow(described_class).to receive(:cached_section).with(:views).and_return(nil)

      result = described_class.call(detail: "summary")
      text = result.content.first[:text]

      expect(text).to include("not available")
    end
  end
end

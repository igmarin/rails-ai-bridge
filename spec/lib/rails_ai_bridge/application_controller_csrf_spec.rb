# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ApplicationController CSRF protection in test fixtures' do
  def fixture_paths
    [
      'spec/internal/app/controllers/application_controller.rb',
      'spec/fixtures/apps/hotwire_crud/app/controllers/application_controller.rb',
      'spec/fixtures/apps/large_schema_crm/app/controllers/application_controller.rb',
      'spec/fixtures/apps/regulated_no_domain/app/controllers/application_controller.rb'
    ]
  end

  def project_root
    Pathname.new(__dir__).join('..', '..', '..').expand_path
  end

  it 'enables protect_from_forgery in all fixture ApplicationControllers' do
    fixture_paths.each do |relative_path|
      absolute_path = project_root.join(relative_path).to_s
      expect(File.read(absolute_path)).to include('protect_from_forgery')
    end
  end
end

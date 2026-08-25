# frozen_string_literal: true

require 'active_record/railtie'

module DatabaseOutage
  class Application < Rails::Application
    config.eager_load = false

    initializer 'database_outage.connect' do
      raise ActiveRecord::ConnectionNotEstablished, 'database unavailable'
    end
  end
end

# frozen_string_literal: true

require 'active_record/railtie'

module DatabaseOutage
  class Application < Rails::Application
    config.eager_load = false
    config.secret_key_base = 'x' * 64

    initializer 'database_outage.connect' do
      raise ActiveRecord::ConnectionNotEstablished, 'database unavailable'
    end
  end
end

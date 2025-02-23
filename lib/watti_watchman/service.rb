module WattiWatchman
  module Service
    module_function

    def cache
      @cache ||= Concurrent::Hash.new
    end
  end
end

require_relative "service/victron_grid_provider"
require_relative "service/victron_grid_feeder"
require_relative "service/charge_controller"
require_relative "service/hass_feeder"
require_relative "service/hass_dynamic_config"
require_relative "service/pyloncan"

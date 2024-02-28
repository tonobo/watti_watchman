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

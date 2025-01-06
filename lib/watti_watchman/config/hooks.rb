module WattiWatchman
  class Config
    module Hooks
      class << self
        def meter_configs
          @meter_configs ||= {}
        end

        def service_configs
          @service_configs ||= {}
        end
      end

      def meter_config(name, &block)
        if Config::Hooks.meter_configs.key?(name)
          raise ConfigError, "meter with #{name.inspect} already registered"
        end

        Config::Hooks.meter_configs[name] = block
      end

      def service_config(name, &block)
        if Config::Hooks.meter_configs.key?(name)
          raise ConfigError, "service with #{name.inspect} already registered"
        end

        Config::Hooks.service_configs[name] = block
      end
    end
  end
end

module WattiWatchman
  module Service
    class HassDynamicConfig
      class ConfigError < WattiWatchman::Error; end

      include WattiWatchman::Logger
      extend WattiWatchman::Config::Hooks

      SUPPORTED_ENTITIES = %w[number select]

      service_config "HassDynamicConfig" do |config, item|
        conn = config.lookup_mqtt_connection(item["mqtt_connection_name"])

        config_handler = WattiWatchman::Service::HassDynamicConfig.new(
          mqtt_params: conn,
          persistent: item["persistent"]
        )
        config_handler.spawn
      end

      attr_reader :config_watchers, :id_property_map

      def initialize(mqtt_params: nil, persistent: false)
        unless mqtt_params.is_a?(Hash)
          raise ArgumentError, "mqtt_params should be a hash for MQTT::Client.connect()"
        end

        @id_property_map = {}
        @persistent = persistent
        @mqtt_params = mqtt_params
        @config_watchers = {}
      end

      def spawn
        Thread.new do
          loop do
            Config.dynamic_configs.each do |service_name, property_hash|
              property_hash.each do |property_name, config|
                submit_hass_config(service_name, property_name, config)
              end
            end
            sleep 60
          end
        end
        Thread.new do 
          mqtt.get do |t, message|
             @config_watchers.each do |_id, callbacks| 
               Array.new(callbacks).each do
                 _1.call(t, message)
               rescue StandardError => err
                 logger.error "HassDynamicConfig: Failed to handle message callback for #{t.inspect} = #{message.inspect}"\
                   ": #{err}\n#{err.backtrace.join("\n")}"
               end
             end 
          end
        end
      end

      def load_entity(config)
        entity = config.dig(:schema, "x_hass_dynamic_config", "entity") 
        if entity.nil?
          raise ConfigError, 
            "HassDynamicConfig failed: missing entity information for #{config}"
        end

        unless SUPPORTED_ENTITIES.include? entity
          raise ConfigError, 
            "HassDynamicConfig failed: wrong entity (#{entity}) for config #{config}."\
            " Supported: #{SUPPORTED_ENTITIES}"
        end

        entity
      end

      def attach_configuration_watcher(id, default_value, entity, config)
        @id_property_map[id] ||= config
        @id_property_map[id][:active_value] = default_value
        mqtt.subscribe(topic("stat_t/#{id}"), topic("cmd_t/#{id}"))
        write_watcher = proc do |t, message|
          next unless t == topic("cmd_t/#{id}")
          value = message
          value = message.to_f if entity == "number"
          logger.debug "PropertyUpdate/cmd_t/#{id}: #{value.inspect}"
          @id_property_map[id][:active_value] = value
          mqtt.publish(topic("stat_t/#{id}"), @id_property_map[id][:active_value], @persistent)
        end
        @config_watchers[id] = [write_watcher]
        # we do want to return early as we don't care about previous configurations
        # so in case previous config was persistent we don't actively read from the recent stat_t
        # otherwise we read and accept changes from stat_t as well
        return unless @persistent

        read_watcher = proc do |t, message|
          next unless t == topic("stat_t/#{id}")
          value = message
          value = message.to_f if entity == "number"
          logger.debug "PropertyUpdate/stat_t/#{id}: #{value.inspect}"
          @id_property_map[id][:active_value] = value
        end
        @config_watchers[id] = [write_watcher, read_watcher]
      end

      def submit_hass_config(service_name, prop_name, config)
        entity = load_entity(config)
        value = config.dig(:data, prop_name)
        if value.nil?
          raise ConfigError, 
            "HassDynamicConfig failed: #{service_name}.#{prop_name} value can't be nil"
        end

        id = "#{service_name.downcase.gsub('/','__')}__#{prop_name}" 
        hassc = config.dig(:schema, "x_hass_dynamic_config").dup
        hassc.delete("entity")

        mqtt.publish(
          "homeassistant/#{entity}/watti_watchman/#{id}/config",
          Oj.dump(hassc.merge(
            {
              name: "#{service_name} #{prop_name}",
              uniq_id: id,
              stat_t: topic("stat_t/#{id}"),
              cmd_t: topic("cmd_t/#{id}"),
              dev: {
                name: "WattiWatchman PowerScheduler",
                mf: "WattiWatchman",
                ids: "WattiWatchman",
              }
            }
          ), mode: :compat)
        )

        attach_configuration_watcher(id, value, entity, config)
      end

      def topic(routing_key)
        "watti_watchman/v#{WattiWatchman::VERSION}/#{routing_key}"
      end

      def mqtt
        @mqtt ||= MQTT::Client.connect(@mqtt_params)
      end
    end
  end
end

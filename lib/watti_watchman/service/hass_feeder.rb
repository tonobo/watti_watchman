require 'digest'

module WattiWatchman
  module Service
    class HassFeeder

      CONFIG_REFRESH_INTERVAL = 60

      include WattiWatchman::Logger
      extend WattiWatchman::Config::Hooks

      service_config "HassFeeder" do |config, item|
        conn = config.lookup_mqtt_connection(item["mqtt_connection_name"])

        feeder = WattiWatchman::Service::HassFeeder.new(
          mqtt_params: conn,
          update_interval: item["update_interval"] || 5
        )
        WattiWatchman::Meter.register("hass-feeder", feeder)
      end

      attr_reader :update_interval

      def initialize(mqtt_params: nil, update_interval: 5)
        unless mqtt_params.is_a?(Hash)
          raise ArgumentError, "mqtt_params should be a hash for MQTT::Client.connect()"
        end
        unless update_interval.is_a?(Numeric)
          raise ArgumentError, "update_interval should be a Numeric"
        end

        @feed_cache = {}
        @update_interval = update_interval
        @mqtt_params = mqtt_params
      end

      def call(metric_name, metric)
        # Early skip if metric is disabled for homeassistant
        return if metric.definition.hass_klass == '-'

        # Metrics can appear not only on singleton level. For example,
        # by using a janitza meter for battery and a different one on
        # grid entry, we need to find a dedicated routing key
        #
        routing_key = metric.definition.metric_id
        metric_instance_name = metric._labels[:name]
        routing_key = "#{routing_key}___#{metric_instance_name}"

        @feed_cache[metric_name] ||= {last_feed_cache_updated_at: 0}

        if WattiWatchman.now - @feed_cache[metric_name][:last_feed_cache_updated_at].to_i > CONFIG_REFRESH_INTERVAL
          submit_hass_config(metric_name, metric, routing_key)
          @feed_cache[metric_name] = { last_feed_cache_updated_at: WattiWatchman.now }
        end

        if WattiWatchman.now - @feed_cache[metric_name][:last_updated_at].to_i > @update_interval
          mqtt.publish(stat_t(routing_key), metric.value.to_f.round(1))
          @feed_cache[metric_name][:last_updated_at] = WattiWatchman.now
        end
      end

      def submit_hass_config(metric_name, metric, routing_key)
        topic = "homeassistant/sensor/watti_watchman/#{routing_key}/config"
        unit = metric.definition.unit
        mqtt.publish(
          topic,
          Oj.dump({
            name: routing_key,
            stat_t: stat_t(routing_key),
            uniq_id: Digest::SHA256.hexdigest(stat_t(routing_key)),
            unit_of_meas: unit == "-" ? nil : unit,
            stat_cla: metric.definition.type,
            dev_cla: metric.definition.hass_klass,
            exp_after: 300,
            dev: {
              name: "WattiWatchman PowerScheduler",
              mf: "WattiWatchman",
              ids: "WattiWatchman",
            }

          }, mode: :compat)
        )
      end

      def stat_t(routing_key)
        "watti_watchman/v#{WattiWatchman::VERSION}/#{routing_key}"
      end

      def mqtt
        @mqtt ||= MQTT::Client.connect(@mqtt_params)
      end
    end
  end
end

module WattiWatchman
  module Service
    class VictronGridFeeder
      include WattiWatchman::Logger
      extend WattiWatchman::Config::Hooks

      service_config "VictronGridFeeder" do |config, item|
        conn = config.lookup_mqtt_connection(item["mqtt_connection_name"])
        meter_obj = config.lookup_meter(item["grid_meter_name"])

        write_prefix = item["write_prefix"]
        unless item["write_prefix"]
          grid_provider = WattiWatchman::Service::VictronGridProvider.new(
            mqtt_params: conn,
          )
          write_prefix = grid_provider.write_prefix
        end

        feeder = WattiWatchman::Service::VictronGridFeeder.new(
          mqtt_params: conn,
          grid_meter: meter_obj,
          write_prefix: write_prefix,
        )
        WattiWatchman::Meter.register("victron-grid-feeder", feeder)
      end

      attr_reader :grid_meter, :write_prefix, :options

      DEFAULTS = {
        power_update_frequency: 0.2,
        common_update_frequency: 1.0
      }.freeze

      def initialize(mqtt_params: nil, grid_meter:, write_prefix:, options: DEFAULTS)
        unless mqtt_params.is_a?(Hash)
          raise ArgumentError, "mqtt_params should be a hash for MQTT::Client.connect()"
        end
        unless grid_meter.is_a?(WattiWatchman::Meter::MeterClassifier)
          raise ArgumentError, "grid_meter should embed MeterClassifier"
        end

        @grid_meter = grid_meter
        @mqtt_params = mqtt_params
        @options = options
        @write_prefix = write_prefix
      end

      # once the object has been registed to meter callback handling
      # this method will be called with metric_name and the WattiWatchman::Meter::Metric
      # object on every WattiWatchman::Meter.cache change
      def call(metric_name, metric)
        return unless metric.origin == grid_meter # metric update belongs to another device
        return unless metric.definition.topic.is_a?(String) # mqtt topic not specified or parse only
        return if metric.definition.topic.start_with?("-") # mqtt topic set to skip by definition

        # reduce update frequency
        is_power_metric = metric.origin
          .yield_self do
            _1.power_metric_classifier(metric_name) || 
              _1.total_power_metric_classifier(metric_name)
          end

        frequency = options.fetch(:common_update_frequency)
        frequency = options.fetch(:power_update_frequency) if is_power_metric

        if metric.cache["last_grid_forward"] && 
            (WattiWatchman.now - metric.cache["last_grid_forward"]) < frequency
          # just updated
          return
        end
        metric.cache["last_grid_forward"] = WattiWatchman.now
        value = metric.value

        if metric.definition.unit == "Wh"
          value = (value.to_f / 1000)
        end

        mqtt.publish(
          write_prefix + "/" + metric.definition.topic,
          Oj.dump({value: value.to_f.round(1)}, mode: :compat))
      end

      def mqtt
        @mqtt ||= MQTT::Client.connect(@mqtt_params)
      end
    end
  end
end

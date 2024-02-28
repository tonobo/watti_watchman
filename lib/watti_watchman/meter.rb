module WattiWatchman
  class Meter
    class PowerMetricNotFoundError < WattiWatchman::Error; end
    class PowerMetricOutdatedError < WattiWatchman::Error; end
    class BatteryMetricNotFoundError < WattiWatchman::Error; end
    class BatteryMetricOutdatedError < WattiWatchman::Error; end

    class << self
      def cache
        @cache ||= Concurrent::Hash.new
      end

      def callbacks
        @callbacks ||= Concurrent::Hash.new
      end

      def register(name, callback=nil, &block)
        return callbacks[name] = callback if callback
        return callbacks[name] = block if block_given?
      end

      def grid_meter(grid_meter=nil)
        return @grid_meter if grid_meter.nil?
        @grid_meter = grid_meter
      end

      def battery_meter(battery_meter=nil)
        return @battery_meter if battery_meter.nil?
        @battery_meter = battery_meter
      end
    end

    module BatteryController 
      def battery_soc(max_age: 300)
        _metric_value(max_age: max_age, value_name: "dc voltage") do |metric_name|
          battery_soc_classifier(metric_name)
        end
      end

      def max_charge_current(max_age: 300)
        _metric_value(max_age: max_age, value_name: "dc voltage") do |metric_name|
          max_charge_current_classifier(metric_name)
        end
      end

      def dc_voltage(max_age: 60)
        _metric_value(max_age: max_age, value_name: "dc voltage") do |metric_name|
          dc_voltage_classifier(metric_name)
        end
      end

      def max_charge_power
        dc_voltage * max_charge_current
      end

      def setpoint(value:, phase:)
        raise "ABSTRACT_METHOD, must be implemented"
      end

      def battery_soc_classifier(metric_name)
        raise "ABSTRACT_METHOD, must be implemented"
      end

      def max_charge_current_classifier(metric_name)
        raise "ABSTRACT_METHOD, must be implemented"
      end

      def dc_voltage_classifier(metric_name)
        raise "ABSTRACT_METHOD, must be implemented"
      end

      private

      def _metric_value(max_age:, value_name:)
        data = WattiWatchman::Meter.cache.find do |metric_name, _cache_entry|
          yield(metric_name)
        end&.last

        raise BatteryMetricNotFoundError, "no #{value_name} value" if data.nil?

        duration = Time.now.to_f - data["metric"]&.timestamp.to_f
        if duration > max_age
          raise BatteryMetricOutdatedError,
            "#{value_name} value outdated, changed #{duration.round(2)}s ago"
        end

        data["metric"].value
      end
    end

    # definition usually gets loaded during runtime and so the object kept available all the time.
    # should be used to declare metrics at some point
    #   * metric -> represents the prometheus metric name, should be prefixed with the module name
    #   * unit -> accorindly to the HASS documentation the unit like "V" for volatage 
    #   * type -> unit type ("measurement" or "total_increasing"), used for homeassitant and prometheus type
    #   * hass_klass -> type class for HASS entities like "energy", "power", "temperature" ...
    #   * topic -> the corresponding topic from VenusOS stuff, will be emitted that way for homeassitant as
    #              well. Can be prefixed with "-" so in case it's not relevant to be pushed back to VenusOS
    Definition = Struct.new(:metric, :unit, :type, :hass_klass, :topic) do
      def metric_data
        @metric_data ||= begin 
                           name, *labels = metric.to_s.split(";")
                           [name, labels.to_h{ _1.split("=") }]
                         end
      end

      def metric_id
        @metric_id ||= begin
                         name, labels = metric_data
                         [name, labels.values].flatten.join("_")
                       end
      end


      def hass_name
        @hass_name ||= metric.split("_").map(&:capitalze).join
      end
    end

    # metric represents an actual measurment pointing to the referenced definition
    class Metric 
      attr_reader :definition, :timestamp
      attr_accessor :value

      def initialize(definition, value, timestamp=Time.now)
        @definition = definition
        @value = value
        @timestamp=timestamp.to_f

        raise ArgumentError, "timestamp cannot be 0" if @timestamp.zero?
      end

      def origin(meter=nil)
        return @origin if meter.nil?

        @origin = meter
      end

      def cache
        Meter.cache[metric_name] ||= {}
      end

      def increment!(value=1.0)
        if definition.type != "total_increasing"
          raise Error, "type must be total_increasing but is #{definition.type.inspect}"
        end

        cache["metric"] ||= self
        cache["metric"].value ||= 0.0
        self.value = cache["metric"].value + value
        update!
      end

      def metric_name
        name, labels = definition.metric_data
        labels.each { |key, value| label(key, value) }

        "%s{%s}" % [
          name,
          _labels.map{ |key, value| %Q(#{key}="#{value}") }.join(", ")
        ] 
      end

      def label(key, value)
        _labels[key] = value
      end

      def seconds_since_last_change
        return 0.0 if cache["last_value_change"].nil? && cache["metric"].nil?

        if cache["last_value_change"].nil?
          return 0.0 if cache["metric"].timestamp.nil?
          return Time.now.to_f - cache["metric"].timestamp
        end

        WattiWatchman.now - cache["last_value_change"]
      end

      def age
        return unless cache["metric"]
        return unless cache["metric"].timestamp

        Time.now.to_f - cache["metric"].timestamp.to_f
      end

      def update!
        to_update = { "metric" => self }
        recent_metric = cache["metric"]
        if cache["metric"]&.value != self.value
          to_update["last_value_change"] = WattiWatchman.now

        end
        cache.merge!(to_update)

        Meter.callbacks.each do |name, block|
          block.call(metric_name, self)
        rescue StandardError => err
          WattiWatchman.logger.warn "failed to run callback #{name.inspect}: #{err}"\
            "\n#{err.backtrace.join("\n")}"
        end
      end

      def _labels
        @_labels ||= {}
      end

      def prometheus_type
        return :gauge if definition.type == "measurement"
        return :counter if definition.type == "total_increasing"

        raise "type #{definition.type.inspect} invalid, unable to convert to prometheus type"
      end

      def to_hass(mqtt)
        return if unit == "-"
        return if hass_klass == "-" 

        if cache.key?("hass_informed_at")
          mqtt.publish() # config
        end
      end
    end
  end
end

require_relative "meter/meter_classifier"
require_relative "meter/janitza"
require_relative "meter/victron"


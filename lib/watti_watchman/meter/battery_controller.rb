module WattiWatchman
  class Meter
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
  end
end


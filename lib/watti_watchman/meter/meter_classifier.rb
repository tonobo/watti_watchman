module WattiWatchman
  class Meter
    module MeterClassifier
      def power(phase:, max_age: 60)
        data = WattiWatchman::Meter.cache.find do |metric_name, _cache_entry|
          phase.to_s.downcase == power_metric_classifier(metric_name).to_s.downcase
        end&.last

        raise PowerMetricNotFoundError, "no power value found for phase '#{phase}'" if data.nil?

        duration = Time.now.to_f - data["metric"]&.timestamp.to_f
        if duration > max_age
          raise PowerMetricOutdatedError,
            "power value outdated, phase '#{phase}' changed #{duration.round(2)}s ago"
        end
        
        data["metric"].value
      end

      def total_power(max_age: 60)
        data = WattiWatchman::Meter.cache.find do |metric_name, _cache_entry|
          total_power_metric_classifier(metric_name)
        end&.last

        raise PowerMetricNotFoundError, "no total power value" if data.nil?

        duration = Time.now.to_f - data["metric"]&.timestamp.to_f
        if duration > max_age
          raise PowerMetricOutdatedError,
            "total power value outdated, changed #{duration.round(2)}s ago"
        end

        data["metric"].value
      end

      def power_metric_classifier(metric_name)
        raise "ABSTRACT_METHOD, must be implemented"
      end

      def total_power_metric_classifier(metric_name)
        raise "ABSTRACT_METHOD, must be implemented"
      end
    end
  end
end

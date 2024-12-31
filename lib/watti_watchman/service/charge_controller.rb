module WattiWatchman
  module Service
    class ChargeController
      extend WattiWatchman::Config::Hooks

      service_config "ChargeController" do |config, item|
        grid_meter_obj      = config.lookup_meter(item["grid_meter_name"])
        battery_meter_obj   = config.lookup_meter(item["battery_meter_name"])
        battery_ctrl_obj    = config.lookup_meter(item["battery_controller_name"])

        cc_options = {
          charge_limits:    (item["charge_limits"]    || {}).transform_keys!(&:to_i),
          discharge_limits: (item["discharge_limits"] || {}).transform_keys!(&:to_i)
        }

        charge_controller = WattiWatchman::Service::ChargeController.new(
          grid_meter:         grid_meter_obj,
          battery_meter:      battery_meter_obj,
          battery_controller: battery_ctrl_obj,
          options:            cc_options
        )

        WattiWatchman::Meter.register("charge-controller", charge_controller)
      end

      attr_reader :grid_meter, :battery_meter, :battery_controller, :options

      UPDATE_FREQUENCY = 0.2

      TARGET_SETPOINT = 0

      # SOC in %  => ChargeRate in W
      CHARGE_LIMITS = {
        0  => 3000,
        90 => 1000,
        97 => 500,
      }

      # SOC in %  => DischargeRate in W
      DISCHARGE_LIMITS = {
        100 => 2000,
        10  => 1000,
        5   => 0,
      }

      DEFAULT = {
        update_frequency: UPDATE_FREQUENCY,
        discharge_limits: DISCHARGE_LIMITS,
        charge_limits: CHARGE_LIMITS,
        target_setpoint: TARGET_SETPOINT,
        control_phase: %w(l1 l2 l3)
      }

      def initialize(grid_meter:, battery_meter:, battery_controller:, options: {})
        unless battery_controller.is_a?(WattiWatchman::Meter::BatteryController)
          raise ArgumentError, "battery_controller must implement BatterController interface"
        end
        unless grid_meter.is_a?(WattiWatchman::Meter::MeterClassifier)
          raise ArgumentError, "grid_meter must implement MeterClassifier interface"
        end
        unless battery_meter.is_a?(WattiWatchman::Meter::MeterClassifier)
          raise ArgumentError, "battery_meter must implement MeterClassifier interface"
        end
        @grid_meter = grid_meter
        @battery_meter = battery_meter
        @battery_controller = battery_controller
        @options = DEFAULT.merge(options)
      end

      def cache
        @cache ||= Concurrent::Hash.new
      end

      def call(metric_name, metric)
        metric_check = [
          grid_meter.total_power_metric_classifier(metric_name),
          battery_meter.total_power_metric_classifier(metric_name), 
          battery_controller.battery_soc_classifier(metric_name)   
        ]
        return unless metric_check.any?

        calculated_setpoint = setpoint
        options.fetch(:control_phase).each do |phase|
          if cache["phase_#{phase}_last_changed"] && 
              (WattiWatchman.now - cache["phase_#{phase}_last_changed"]) < options.fetch(:update_frequency)
            return
          end

          cache["phase_#{phase}_last_changed"] = WattiWatchman.now
          battery_controller.setpoint(
            value: calculated_setpoint / options.fetch(:control_phase).size,
            phase: phase
          )
        end
      end

      def setpoint
        soc = battery_controller.battery_soc

        discharge_limits = [ 100, Float::INFINITY ]
        options.fetch(:discharge_limits).sort_by { |percent, _limit| percent }.to_h.find do |percent, limit|
          next if soc > percent

          discharge_limits = [ percent, limit ]
        end

        charge_limits = [ 0, 0 ]
        options.fetch(:charge_limits).sort_by { |percent, _limit| percent }.to_h.each do |percent, limit|
          next if soc < percent

          charge_limits = [ percent, limit ] 
        end
        min_threshold = discharge_limits.last * -1
        max_threshold = charge_limits.last

        diff = (grid_meter.total_power * -1) + battery_meter.total_power + 
          options.fetch(:target_setpoint)

        return diff if (min_threshold..max_threshold).include?(diff)
        return min_threshold if diff < min_threshold
        return max_threshold if diff > max_threshold
      end
    end
  end
end


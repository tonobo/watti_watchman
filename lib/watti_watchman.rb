# frozen_string_literal: true

require 'logger'
require "rmodbus"
require "mqtt"
require "concurrent-ruby"
require "oj"
require 'async/scheduler'

module WattiWatchman
  class Error < StandardError; end

  require_relative "watti_watchman/version"
  require_relative "watti_watchman/logger"
  require_relative "watti_watchman/meter"
  require_relative "watti_watchman/service"

  module_function

  extend WattiWatchman::Logger
  
  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def auto_retry(name, &block)
    loop do
      block.call
    rescue StandardError => err
      logger.error("#{name.inspect} failed, auto retry enabled: "\
                   "#{err}\n#{err.backtrace.join("\n")}")
      sleep(1)
    end
  end

  # TODO: discover from battery_controller
  CONTROL_MODE="single-phase"

  # battery_controller settings
  THROTTLE = 300 # watt
  STATIC_SETPOINT = 50


  class Service::ChargeController
    attr_reader :grid_meter, :battery_meter, :battery_controller, :options

    UPDATE_FREQUENCY = 0.2

    def initialize(grid_meter:, battery_meter:, battery_controller:, options: {})
      @grid_meter = grid_meter
      @battery_meter = battery_meter
      @battery_controller = battery_controller
      @options = options
    end

    def cache
      @cache ||= Concurrent::Hash.new
    end

    def call(metric_name, metric)
      # check single-phase / three-phase

      metric_check = [
        grid_meter.power_metric_classifier(metric_name),
        battery_meter.power_metric_classifier(metric_name), 
        battery_controller.battery_soc_classifier(metric_name)   
      ]
      return unless metric_check.any?
      phase = :l1

      if cache["phase_#{phase}_last_changed"] && 
          (WattiWatchman.now - cache["phase_#{phase}_last_changed"]) < UPDATE_FREQUENCY 
        return
      end

      cache["phase_#{phase}_last_changed"] = WattiWatchman.now
      battery_controller.setpoint(value: setpoint, phase: phase)
    end

    def setpoint
      max_threshold = 3000
      max_threshold = 500 if battery_controller.battery_soc > 93
      max_threshold = 0 if battery_controller.battery_soc > 97

      min_threshold = -2000
      min_threshold = -500 if battery_controller.battery_soc < 20
      min_threshold = 0 if battery_controller.battery_soc < 10

      diff = (grid_meter.total_power * -1) + battery_meter.total_power + STATIC_SETPOINT

      return diff if (min_threshold..max_threshold).include?(diff)
      return min_threshold if diff < min_threshold
      return max_threshold if diff > max_threshold
    end
  end

  WattiWatchman::Meter.register("power-control") do |metric_name, metric|
    battery = WattiWatchman::Meter.battery_meter
    grid = WattiWatchman::Meter.grid_meter

    next if battery.nil?
    next if grid.nil?

    next if [battery, grid].include?(metric.origin)

    #TODO battery_controller
    phase = nil
    case CONTROL_MODE
    when "single-phase"
      next unless metric.origin.total_power_metric_classifier(metric_name, metric)
    when "three-phase"
      phase = metric.origin.power_metric_classifier(metric_name, metric)
      next unless phase
    else
      raise Error, "should not happend"
    end
    # a necessary power value changed, so reset power setpoint

    adjustment = (grid.power * -1) + battery.power + STATIC_SETPOINT
    adjustment = THROTTLE if adjustment > THROTTLE
    batter_controller.setpoint(adjustment)
  end

  def go
    mqtt_venus_params = {host: "10.100.6.134", port: 1883} 

    grid_provider = WattiWatchman::Service::VictronGridProvider.new(
      mqtt_params: mqtt_venus_params,
    )

    grid_meter = WattiWatchman::Meter::Janitza.new(
      name: "hak", host: "10.100.6.27", port: 502, unit: 2
    ).tap { _1.spawn }

    battery_janitza_meter = WattiWatchman::Meter::Janitza.new(
      name: "battery", host: "10.100.6.229", port: 8899, unit: 1, interval: 0.25
    ).tap { _1.spawn }

    battery_victron = WattiWatchman::Meter::Victron.new(
      name: "battery", mqtt_params: mqtt_venus_params, id: ENV.fetch("VRM_ID")
    ).tap { _1.spawn }

    victron_feeder = WattiWatchman::Service::VictronGridFeeder.new(
      mqtt_params: mqtt_venus_params,
      grid_meter: grid_meter,
      write_prefix: grid_provider.write_prefix
    )

    WattiWatchman::Meter.register("victron-feeder", victron_feeder)

    charge_controller = WattiWatchman::Service::ChargeController.new(
      grid_meter: grid_meter,
      #battery_meter: battery_victron,
      battery_meter: battery_janitza_meter,
      battery_controller: battery_victron
    )

    WattiWatchman::Meter.register("charge-controller", charge_controller)

  end
end

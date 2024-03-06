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

  def go
    mqtt_venus_params = {host: "10.100.6.134", port: 1883} 

    grid_provider = WattiWatchman::Service::VictronGridProvider.new(
      mqtt_params: mqtt_venus_params,
    )

    grid_meter = WattiWatchman::Meter::Janitza.new(
      name: "hak", host: "10.100.6.27", port: 502, unit: 2
    ).tap { _1.spawn }

    battery_janitza_meter = WattiWatchman::Meter::Janitza.new(
      name: "battery", host: "10.100.6.25", port: 502, unit: 1,
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
      battery_controller: battery_victron,
      options: {
        charge_limits: {
          0  => 9000,
          90 => 2000,
          97 => 1000,
          99 => 500,
        },
        discharge_limits: {
          100 => 6000,
          10  => 1000,
          5   => 0,
        }
      }
    )

    WattiWatchman::Meter.register("charge-controller", charge_controller)

  end
end

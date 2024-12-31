# frozen_string_literal: true

require 'logger'
require "rmodbus"
require "mqtt"
require "concurrent-ruby"
require "oj"
require 'async/scheduler'
require 'json_schemer'
require 'yaml'

module WattiWatchman
  class Error < StandardError; end

  require_relative "watti_watchman/logger"
  require_relative "watti_watchman/config"
  require_relative "watti_watchman/version"
  require_relative "watti_watchman/meter"
  require_relative "watti_watchman/service"

  module_function

  extend WattiWatchman::Logger

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def go
    config = Config.load

    config.config_data["meters"].each do |meter_cfg|
      callback = WattiWatchman::Config::Hooks.meter_configs[meter_cfg["type"]]
      next callback.call(config, meter_cfg) if callback

      raise "unable to find Meter configuration hook for type '#{meter_cfg['type']}'"
    end

    config.config_data["services"].each do |svc_cfg|
      callback = WattiWatchman::Config::Hooks.service_configs[svc_cfg["type"]]
      next callback.call(config, svc_cfg) if callback

      raise "unable to find Service configuration hook for type '#{svc_cfg['type']}'"
    end
  end
end

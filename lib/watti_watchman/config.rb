# frozen_string_literal: true

require 'json_schemer'
require 'yaml'

module WattiWatchman
  class Config < Struct.new(:config_data, :schemer)
    require_relative "config/hooks"

    class << self
      def dynamic_configs
        @dynamic_configs ||= {}
      end
    end

    class ConfigError < WattiWatchman::Error; end

    SCHEMA_BASE_PATH   = File.expand_path("../../../schemas", __FILE__)
    SUPPORTED_DYNAMIC_KIND = %w[Meter Service]

    extend WattiWatchman::Logger

    def self.load(config=nil)
      config ||= YAML.safe_load(
        File.read(
          File.expand_path("../../../watti_watchman.yml", __FILE__))
      )
      main_schema = File.join(SCHEMA_BASE_PATH, "main_schema.yml")

      main_schema_data = YAML.safe_load(File.read(main_schema))

      definitions = Dir[File.join(SCHEMA_BASE_PATH, "*.yml")].map do |fname|
        next if fname.include?("main_schema.yml")
        schema = YAML.safe_load(File.read(fname))
        raise ConfigError, "Schema invalid: #{fname} is missing $id" unless schema.key?("$id")
        [URI(schema["$id"]), schema]
      end.compact.to_h

      # just to make sure everything is json compatible
      config_data = JSON.parse(Oj.dump(config, mode: :strict))

      config = JSONSchemer::Configuration.new(
        insert_property_defaults: true,
        before_property_validation: proc do |data, property, property_schema, parent| 
          if property_schema.is_a?(Hash) && property_schema["x_dynamic_config"]
            kind = parent.dig("properties", "kind", "const")
            unless SUPPORTED_DYNAMIC_KIND.include?(kind)
              raise ConfigError, "Schema validation failed: kind must be one of #{SUPPORTED_DYNAMIC_KIND}"
            end

            type = parent.dig("properties", "type", "const")
            if type.nil? || kind.nil?
              raise ConfigError, "Schema validation failed: prop #{property.inspect} has" \
                "dynamic configration enabled, but kind and type must be specified at parent"
            end

            type = "#{kind}/#{type}"
            value = { property: property, schema: property_schema, parent: parent, data: data}

            self.dynamic_configs[type] ||= {}
            self.dynamic_configs[type] = { property => value} 
          end
        end
      )

      schemer = JSONSchemer.schema(
        main_schema_data,
        ref_resolver: definitions.to_proc,
        configuration: config,
      )

      unless schemer.valid?(config_data)
        errors = schemer.validate(config_data).to_a.join(",\n")
        raise ConfigError, "Configuration invalid: #{errors}"
      end

      Config.new(config_data, schemer)
    end

    def mqtt_connections
      mqtt_connections = {}
      config_data["mqtt_connections"].each do |conn|
        mqtt_connections[conn["name"]] = {
          host: conn["host"],
          port: conn["port"]
        }
      end
      mqtt_connections
    end

    def lookup_mqtt_connection(name)
      unless mqtt_connections.key?(name)
        raise ConfigError, "MQTT connection '#{name}' not found in config!"
      end
      mqtt_connections[name]
    end

    def lookup_meter(name)
      meter_config = config_data["meters"].find{ _1["name"] == name }
      meter_obj = WattiWatchman::Meter.lookup(name)
      return meter_obj if meter_config && meter_obj

      raise ConfigError, "Meter '#{name}' not configured!" unless meter_config
      raise ConfigError, "Meter '#{name}' not registered!"
    end
  end
end

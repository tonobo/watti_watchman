module WattiWatchman
  module Service
    class VictronGridProvider
      include WattiWatchman::Logger

      class GridRegisterTimeoutError < Error; end

      attr_reader :client_id, :service_name, :timeout

      def initialize(mqtt_params:, service_name: "grid_meter", client_id: "watti_grid", timeout: 5)
        unless mqtt_params.is_a? Hash
          raise ArgumentError, "mqtt_params should be a hash for MQTT::Client.connect()"
        end
        @client_id = client_id
        @service_name = service_name
        @mqtt_params = mqtt_params
        @timeout = timeout
      end

      def mqtt
        @mqtt ||= MQTT::Client.connect(@mqtt_params.merge(
          client_id: client_id,
          will_topic: "device/#{client_id}/Status",
          will_payload: Oj.dump(status.merge(connected: 0), mode: :compat)
        ))
      end

      def status
        {
          clientId: client_id,
          version: "WattiWatchman v#{WattiWatchman::VERSION}",
          services: { service_name => "grid"},
        }
      end

      def write_prefix
        @write_prefix ||=
          begin
            mqtt.subscribe("device/#{client_id}/#")
            mqtt.publish("device/#{client_id}/Status",
                         Oj.dump(status.merge(connected: 1), mode: :compat))
            start = WattiWatchman.now
            loop do
              raise(GridRegisterTimeoutError) if (WattiWatchman.now - start) > timeout

              next sleep(0.01) if mqtt.queue_empty?
              topic, message = mqtt.get

              logger.debug "Received: #{topic.inspect} => #{message}"
              next unless topic == "device/#{client_id}/DBus"

              break Oj.safe_load(message).yield_self do |value|
                "W/#{value.fetch("portalId")}/grid/#{value.fetch("deviceInstance")
                  .fetch(service_name)}"
              end
            end
          end
      end
    end
  end
end

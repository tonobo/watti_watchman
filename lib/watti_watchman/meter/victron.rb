module WattiWatchman
  class Meter
    class Victron
      include MeterClassifier
      include Logger
      include BatteryController

      # Register order is mandatory as it's being used to efficently fetch all metrics once via modbus
      Registers = [
        #  metric_name                         unit   type      hass_class       (VE) mqtt    
        %w(ac_in_power;phase=l1                W   measurement  power            Ac/ActiveIn/L1/P),
        %w(ac_in_power;phase=l2                W   measurement  power            Ac/ActiveIn/L2/P),
        %w(ac_in_power;phase=l3                W   measurement  power            Ac/ActiveIn/L3/P),
        %w(ac_in_power_total                   W   measurement  power            Ac/ActiveIn/P),

        %w(ac_in_apparent_power;phase=l1       VA  measurement  apparent_power   Ac/ActiveIn/L1/S),
        %w(ac_in_apparent_power;phase=l2       VA  measurement  apparent_power   Ac/ActiveIn/L2/S),
        %w(ac_in_apparent_power;phase=l3       VA  measurement  apparent_power   Ac/ActiveIn/L3/S),
        %w(ac_in_apparent_power_total          VA  measurement  apparent_power   Ac/ActiveIn/S),

        %w(ac_in_current;phase=l1              A   measurement  current          Ac/ActiveIn/L1/I),
        %w(ac_in_current;phase=l2              A   measurement  current          Ac/ActiveIn/L2/I),
        %w(ac_in_current;phase=l3              A   measurement  current          Ac/ActiveIn/L3/I),
        %w(ac_in_current_total                 A   measurement  current          Ac/ActiveIn/I),

        %w(ac_in_voltage;phase=l1              V   measurement  voltage          Ac/ActiveIn/L1/V),
        %w(ac_in_voltage;phase=l2              V   measurement  voltage          Ac/ActiveIn/L2/V),
        %w(ac_in_voltage;phase=l3              V   measurement  voltage          Ac/ActiveIn/L3/V),

        %w(ac_out_power;phase=l1               W   measurement  power            Ac/Out/L1/P),
        %w(ac_out_power;phase=l2               W   measurement  power            Ac/Out/L2/P),
        %w(ac_out_power;phase=l3               W   measurement  power            Ac/Out/L3/P),
        %w(ac_out_power_total                  W   measurement  power            Ac/Out/P),

        %w(ac_out_apparent_power;phase=l1      VA  measurement  apparent_power   Ac/Out/L1/S),
        %w(ac_out_apparent_power;phase=l2      VA  measurement  apparent_power   Ac/Out/L2/S),
        %w(ac_out_apparent_power;phase=l3      VA  measurement  apparent_power   Ac/Out/L3/S),
        %w(ac_out_apparent_power_total         VA  measurement  apparent_power   Ac/Out/S),

        %w(ac_out_current;phase=l1             A   measurement  current          Ac/Out/L1/I),
        %w(ac_out_current;phase=l2             A   measurement  current          Ac/Out/L2/I),
        %w(ac_out_current;phase=l3             A   measurement  current          Ac/Out/L3/I),
        %w(ac_out_current_total                A   measurement  current          Ac/Out/I),

        %w(ac_out_voltage;phase=l1             V   measurement  voltage          Ac/Out/L1/V),
        %w(ac_out_voltage;phase=l2             V   measurement  voltage          Ac/Out/L2/V),
        %w(ac_out_voltage;phase=l3             V   measurement  voltage          Ac/Out/L3/V),

        %w(ac_out_voltage_frequency;phase=l1   %   measurement  frequency        Ac/Out/L1/F),
        %w(ac_out_voltage_frequency;phase=l2   %   measurement  frequency        Ac/Out/L2/F),
        %w(ac_out_voltage_frequency;phase=l3   %   measurement  frequency        Ac/Out/L3/F),

        %w(dc_power                      W   measurement  power            Dc/0/Power),
        %w(dc_current                    A   measurement  current          Dc/0/Current),
        %w(dc_voltage                    V   measurement  voltage          Dc/0/Voltage),
        [ "dc_soc",                     "%","measurement","battery",      %r(/vebus/\d+/Soc$)],
        [ "dc_max_charge_current",      "A","measurement","current",      %r(/battery/\d+/Info/MaxChargeCurrent$)],
      ].to_h { [_1[-1], Definition.new("victron_"+_1[0], *_1[1..-1])]}

      Metrics = [
        %w(emitted_ac_power_setpoint;phase=l1   W measurement power AcPowerSetpoint/L1),
        %w(emitted_ac_power_setpoint;phase=l2   W measurement power AcPowerSetpoint/L2),
        %w(emitted_ac_power_setpoint;phase=l3   W measurement power AcPowerSetpoint/L3),

        %w(processing_reconnect_count_total          -  total_increasing  - -),

        %w(messages_consumed_total          -  total_increasing  - -),
        %w(messages_payload_invalid_total   -  total_increasing  - -),
        %w(messages_value_null_total        -  total_increasing  - -),
        %w(messages_processed_total         -  total_increasing  - -),
      ].to_h{ [_1[0], Definition.new("victron_#{_1[0]}", *_1[1..-1]) ]}

      attr_reader :name, :id, :mqtt_params, :vebus_id, :keepalive_interval

      KEEPALIVE_INTERVAL = 20
      FULL_CACHE_REFRESH = 240

      def initialize(name:, id:, mqtt_params:, keepalive_interval: KEEPALIVE_INTERVAL)
        @name = name
        @mqtt_params = mqtt_params
        @id = id
        @keepalive_interval = keepalive_interval
      end

      def mqtt
        @mqtt ||= MQTT::Client.connect(mqtt_params)
      end

      def setpoint(value:, phase:)
        if vebus_id.nil?
          raise Error, "vebus id not yet discovered, subcribe first"
        end

        unless %w(l1 l2 l3).include?(phase.to_s.downcase)
          raise ArgumentError, "phase not valid"
        end

        return if value.nil?

        m("emitted_ac_power_setpoint;phase=#{phase.to_s.downcase}")
          .tap { _1.value = value }
          .update!
        mqtt.publish("W/#{id}/vebus/#{vebus_id}/Hub4/#{phase.to_s.upcase}/AcPowerSetpoint",
                             Oj.dump({value: value}, mode: :compat))
      end

      def battery_soc_classifier(metric_name)
        metric_name.match?(/dc_soc/) &&
          metric_name.include?(%Q(name="#{name}"))
      end

      def max_charge_current_classifier(metric_name)
        metric_name.match?(/dc_max_charge_current/) &&
          metric_name.include?(%Q(name="#{name}"))
      end

      def dc_voltage_classifier(metric_name)
        metric_name.match?(/dc_voltage/) &&
          metric_name.include?(%Q(name="#{name}"))
      end

      def power_metric_classifier(metric_name)
          if metric_name.include?("ac_in_power") &&
            metric_name.match?(/phase="l\d+"/i) &&
            metric_name.match?(/name="#{name}"/i)

            return metric_name[/phase="(l\d+)"/i, 1]
          end
      end

      def total_power_metric_classifier(metric_name)
        metric_name.include?("ac_in_power_total") &&
          metric_name.match?(/name="#{name}"/i)
      end

      def spawn
        Thread.new do
          loop do
            self.do()
          rescue StandardError => err
            logger.error "caught error: #{err}, resetting connection"
            m("processing_reconnect_count_total").increment!
          end
        end
      end

      def m(name)
        Metric.new(Metrics[name], 0.0).tap do |metric|
          metric.origin(self)
          metric.label(:name, self.name)
          metric.label(:id, id)
        end
      end

      def do
        mqtt.subscribe("N/#{id}/#")
        mqtt.publish("R/#{id}/keepalive", "")
        last_keepalive_at = { full: WattiWatchman.now, partial: WattiWatchman.now }
        loop do
          # keepalive without params is necessary to make sure the cache is up2date.
          # Usually there shouldn't be missed anything, but there are some metric age
          # checks necessary which could lead to issues. In theory when no value has been missed
          # then there wouldn't be any need to age checking but it's about my and others software.
          if (WattiWatchman.now - last_keepalive_at[:full].to_f) > FULL_CACHE_REFRESH
            mqtt.publish("R/#{id}/keepalive", "")
            last_keepalive_at[:full] = WattiWatchman.now
          elsif (WattiWatchman.now - last_keepalive_at[:partial].to_f) > keepalive_interval
            mqtt.publish("R/#{id}/keepalive", %Q({ "keepalive-options" : ["suppress-republish"] }))
            last_keepalive_at[:partial] = WattiWatchman.now
          end

          until mqtt.queue_empty?
            topic, payload = mqtt.get
            m("messages_consumed_total").increment!

            if vebus_id.nil? && (result = topic[%r(N/#{id}/vebus/(\d+)/),1])
              logger.info "Found vebus_id = #{result.inspect}"
              @vebus_id = result
            end

            definition = Registers.find do |key, value|
              case key
              when String
                topic.end_with?(key)
              when Regexp
                topic.match?(key)
              else
                raise Error, "#{key.inspect}: key class undefined" 
              end
            end&.last
            next if definition.nil?

            # precision loss isn't a thing here, so keeping float values as float.
            # primary reason is to make debugging easier
            value = (Oj.load(payload, mode: :compat, bigdecimal_load: :float) rescue nil)
            if value.nil?
              m("messages_payload_invalid_total")
                .tap{ _1.label(:definition, definition.metric_id) }
                .increment!
              next
            end

            if value["value"].nil?
              m("messages_value_null_total")
                .tap{ _1.label(:definition, definition.metric_id) }
                .increment!
              next
            end

            Metric.new(definition, value["value"])
              .tap{ _1.label(:name, self.name) }
              .tap{ _1.label(:id, id) }
              .tap{ _1.origin(self) }
              .tap{ _1.cache["learned_from"] = topic }
              .update!
            m("messages_processed_total").increment!
          end
          
          sleep 0.01
        end
      end

    end
  end
end


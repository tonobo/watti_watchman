module WattiWatchman
  class Meter
    class Janitza
      include MeterClassifier
      include WattiWatchman::Logger
      
      # Register order is mandatory as it's being used to efficently fetch all metrics once via modbus
      Registers = [
        #  metric_name                             unit   type              hass_class       (VE) mqtt    
        %w(voltage;phase=l1                        V   measurement       voltage          Ac/L1/Voltage       ),
        %w(voltage;phase=l2                        V   measurement       voltage          Ac/L2/Voltage       ),
        %w(voltage;phase=l3                        V   measurement       voltage          Ac/L3/Voltage       ),

        %w(voltage;phase=l1_l2                     V   measurement       voltage          -Ac/L1-L2/Voltage   ),
        %w(voltage;phase=l2_l3                     V   measurement       voltage          -Ac/L2-L3/Voltage   ),
        %w(voltage;phase=l1_l3                     V   measurement       voltage          -Ac/L1-L3/Voltage   ),

        %w(current;phase=l1                        A   measurement       current          Ac/L1/Current       ),
        %w(current;phase=l2                        A   measurement       current          Ac/L2/Current       ),
        %w(current;phase=l3                        A   measurement       current          Ac/L3/Current       ),
        %w(current_total                           A   measurement       current          Ac/Current          ),

        %w(real_power;phase=l1                     W   measurement       power            Ac/L1/Power         ),
        %w(real_power;phase=l2                     W   measurement       power            Ac/L2/Power         ),
        %w(real_power;phase=l3                     W   measurement       power            Ac/L3/Power         ),
        %w(real_power_total                        W   measurement       power            Ac/Power            ),

        %w(apparent_power;phase=l1                 VA  measurement       apparent_power   -Ac/L1/ApparentPower),
        %w(apparent_power;phase=l2                 VA  measurement       apparent_power   -Ac/L2/ApparentPower),
        %w(apparent_power;phase=l3                 VA  measurement       apparent_power   -Ac/L3/ApparentPower),
        %w(apparent_power_total                    VA  measurement       apparent_power   -Ac/ApparentPower   ),

        %w(reactive_power;phase=l1                 var measurement       reactive_power   -Ac/L1/ReactivePower),
        %w(reactive_power;phase=l2                 var measurement       reactive_power   -Ac/L2/ReactivePower),
        %w(reactive_power;phase=l3                 var measurement       reactive_power   -Ac/L3/ReactivePower),
        %w(reactive_power_total                    var measurement       reactive_power   -Ac/ReactivePower   ),

        %w(power_factor;phase=l1                   -   measurement       power_factor     -Ac/L1/PowerFactor  ),
        %w(power_factor;phase=l2                   -   measurement       power_factor     -Ac/L2/PowerFactor  ),
        %w(power_factor;phase=l3                   -   measurement       power_factor     -Ac/L3/PowerFactor  ),

        %w(frequency                               Hz  measurement       frequency        Ac/Frequency        ),

        %w(rotation_field                          -   measurement       -                -                   ),

        %w(real_energy_l1_total                    Wh  total_increasing  energy           -Ac/L1/Energy       ),
        %w(real_energy_l2_total                    Wh  total_increasing  energy           -Ac/L2/Energy       ),
        %w(real_energy_l3_total                    Wh  total_increasing  energy           -Ac/L3/Energy       ),
        %w(real_energy_total                       Wh  total_increasing  energy           -Ac/Energy          ),

        %w(real_energy_l1_consumed_total           Wh  total_increasing  energy           Ac/L1/Energy/Reverse),
        %w(real_energy_l2_consumed_total           Wh  total_increasing  energy           Ac/L2/Energy/Reverse),
        %w(real_energy_l3_consumed_total           Wh  total_increasing  energy           Ac/L3/Energy/Reverse),
        %w(real_energy_consumed_total              Wh  total_increasing  energy           Ac/Energy/Reverse   ),

        %w(real_energy_l1_delivered_total          Wh  total_increasing  energy           Ac/L1/Energy/Forward),
        %w(real_energy_l2_delivered_total          Wh  total_increasing  energy           Ac/L2/Energy/Forward),
        %w(real_energy_l3_delivered_total          Wh  total_increasing  energy           Ac/L3/Energy/Forward),
        %w(real_energy_delivered_total             Wh  total_increasing  energy           Ac/Energy/Forward   ),
      ].map { Definition.new("janitza_"+_1[0], *_1[1..4]) }

      Metrics = [
        %w(collecting_registers_seconds_total  s  total_increasing  - -),
        %w(processing_registers_seconds_total  s  total_increasing  - -),
        %w(processing_registers_count_total    -  total_increasing  - -),
        %w(processing_reconnect_count_total    -  total_increasing  - -),
        %w(processing_errors_count_total       -  total_increasing  - -),

        %w(collecting_registers_pressure_count_total    -  total_increasing  - -),
      ].to_h{ [_1[0], Definition.new("janitza_#{_1[0]}", *_1[1..-1]) ]}

      # janitza meters usuallly have a modbus refresh interval of 200ms
      # by having 100ms interval we're maybe 100ms late for fetching the power metrics
      # NOTE: would be cool to have automatic alignment to nearly reach 200ms for real
      # but not necessary at this point
      INTERVAL = 0.1

      attr_reader :name, :host, :port, :unit, :interval

      def initialize(name:, host:, port:, unit:, interval: INTERVAL)
        @name = name
        @host = host
        @port = port
        @unit = unit
        @interval = interval
      end

      def m(name)
        Metric.new(Metrics[name], 0.0).tap do |metric|
          metric.origin(self)
          metric.label(:name, self.name)
        end
      end

      def _sleep_max(duration)
        if duration > interval
          m("collecting_registers_pressure_count_total").increment!
          return
        end
        
        sleep(interval - duration)
      end

      def power_metric_classifier(metric_name)
          if metric_name.include?("real_power") &&
            metric_name.match?(/phase="l\d+"/i) &&
            metric_name.match?(/name="#{name}"/i)

            return metric_name[/phase="(l\d+)"/i, 1]
          end
      end

      def total_power_metric_classifier(metric_name)
        metric_name.include?("real_power_total") &&
          metric_name.match?(/name="#{name}"/i)
      end

      def spawn
        Thread.new do
          loop do
            self.do()
          rescue StandardError => err
            logger.error "caught error: #{err}, resetting connection"
            m("processing_reconnect_count_total").increment!
            sleep 1
          end
        end
      end

      def do
        error_counter = 0
        ModBus::TCPClient.new(host, port) do |client|
          client.with_slave(unit) do |unit|
            loop do
              started_at = WattiWatchman.now
              registers = unit.query("\x3"+19000.to_word + (Registers.size*2).to_word)&.unpack("g*")
              if registers.nil?
                m("processing_errors_count_total").tap{ _1.label(:error, "register_query_error") }.increment!
                next _sleep_max(WattiWatchman.now - started_at)
              end

              processed_registers_at = WattiWatchman.now
              timestamp = Time.now
              m("collecting_registers_seconds_total").increment!(processed_registers_at - started_at)

              if registers.size != Registers.size
                # this case only happend on the waveshare device so far
                m("processing_errors_count_total")
                  .tap{ _1.label(:error, "register_overrun") }
                  .increment!
                next _sleep_max(WattiWatchman.now - started_at)
              end

              registers.each.with_index do |value, index|
                Metric.new(Registers[index], value, timestamp).tap do |metric|
                  metric.origin(self)
                  metric.label(:name, name)
                end.update!
              end
              process_duration = WattiWatchman.now - started_at

              m("processing_registers_count_total").increment!(registers.size)
              m("processing_registers_seconds_total").increment!(process_duration)

              error_counter = 0
              _sleep_max(process_duration)
            rescue ModBus::Errors::ModBusTimeout
              m("processing_errors_count_total").tap{ _1.label(:error, "modbus_timeout") }.increment!
              _sleep_max(WattiWatchman.now - started_at)
            rescue ModBus::Errors::ModBusException
              m("processing_errors_count_total").tap{ _1.label(:error, "unkown_modbus_error") }.increment!
              _sleep_max(WattiWatchman.now - started_at)
            rescue StandardError => err
              error_counter += 1
              m("processing_errors_count_total").tap{ _1.label(:error, "unkown_error") }.increment!
              logger.error("modbus processing error for name(#{name}): "\
                           "#{err}\n#{err.backtrace.join("\n")}")
              if error_counter > 5
                raise err
              else
                _sleep_max(WattiWatchman.now - started_at)
              end
            end
          end
        end
      end
    end
  end
end

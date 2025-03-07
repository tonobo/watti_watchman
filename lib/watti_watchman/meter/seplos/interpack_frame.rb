require_relative './request'

module WattiWatchman
  class Meter
    class Seplos
      class InterpackFrame
        Registers = [
          #  metric_nam                      unit   type                   hass_class
          %w(cell_highest                       V   measurement            voltage    ),
          %w(cell_lowest                        V   measurement            voltage    ),
          %w(temperature_highest                °C  measurement            temperature),
          %w(temperature_lowest                 °C  measurement            temperature),
          %w(current                            A   measurement            current    ),
          %w(pack_voltage                       V   measurement            voltage    ),
          %w(residual_capacity                  Ah  measurement            energy     ),
          %w(battery_capacity                   Ah  measurement            energy     ),
          %w(soc                                %   measurement            battery    ),
          %w(port_voltage                       V   measurement            voltage    ),
        ].to_h { [_1[0], Definition.new("seplos_interpack_"+_1[0], *_1[1..3], "-")] }

        attr_reader :bms

        def initialize(bms:)
          @bms = bms
        end

        def m(name, value=0)
          Metric.new(Registers.fetch(name), value).tap do |metric|
            metric.origin(self)
            metric.label(:bms, bms.name)
          end
        end

        def process(response)
          offset = 16
          metrics = []
          metrics << m("cell_highest", response[offset, 4].to_i(16) * 0.1); offset += 4
          metrics << m("cell_lowest", response[offset, 4].to_i(16) * 0.1); offset += 4
          metrics << m("temperature_highest", (response[offset, 4].to_i(16) + 2731) * 0.1); offset += 4
          metrics << m("temperature_lowest", (response[offset, 4].to_i(16) + 2731) * 0.1); offset += 4
          metrics << m("current", (response[offset, 4].to_i(16)) * 0.01); offset += 4
          metrics << m("pack_voltage", (response[offset, 4].to_i(16)) * 0.01); offset += 4
          metrics << m("residual_capacity", (response[offset, 4].to_i(16)) * 0.01); offset += 4
          metrics << m("battery_capacity", (response[offset, 4].to_i(16)) * 0.01); offset += 4
          metrics << m("soc", (response[offset, 4].to_i(16)) * 0.1); offset += 4
          metrics << m("port_voltage", (response[offset, 4].to_i(16)) * 0.1); offset += 4

          metrics.each(&:update!)
        end
      end
    end
  end
end

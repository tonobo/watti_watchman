require_relative './request'

module WattiWatchman
  class Meter
    class Seplos
      class TelemetryRequest < Seplos::Request
        Registers = [
          #  metric_nam                      unit   type                   hass_class
          %w(charge_rate                        A   measurement            current    ),
          %w(total_battery_voltage              V   measurement            voltage    ),
          %w(residual_capacity                  Ah  measurement            energy     ),
          %w(battery_capacity                   Ah  measurement            energy     ),
          %w(rated_capacity                     Ah  measurement            energy     ),
          %w(port_voltage                       V   measurement            voltage    ),
          %w(soc                                %   measurement            battery    ),
          %w(soh                                %   measurement            battery    ),
          %w(cycles_count_total                 -   total_increasing       -          ),
          %w(cell_voltage                       V   measurement            voltage    ),
          %w(temperature_celsius                °C  measurement            temperature),
        ].to_h { [_1[0], Definition.new("seplos_telemetry_"+_1[0], *_1[1..3], "-")] }

        attr_reader :bms

        def initialize(bms:)
          @bms = bms
          super(function: 0x42)
        end

        def m(name, value=0)
          Metric.new(Registers.fetch(name), value).tap do |metric|
            metric.origin(self)
            metric.label(:bms, bms.name)
          end
        end

        def process(response)
          offset = 16
          cell_count_hex = response[offset, 2]; offset += 2
          cell_count = cell_count_hex.to_i(16)

          cell_count.times do |i|
            cell_hex = response[offset, 4]
            value = cell_hex.to_i(16).to_f / 1000.0
            m("cell_voltage", value)
              .tap{ _1.label(:cell, (i+1).to_s) }
              .update!
            offset += 4
          end

          temp_count_hex = response[offset, 2]; offset += 2
          temp_count = temp_count_hex.to_i(16)
          temp_count.times do |i|
            temp_hex = response[offset, 4]
            raw = temp_hex.to_i(16)
            # temperatures are measured in K
            value = ((raw - 2731) / 10.0)
            m("temperature_celsius", value)
              .tap{ _1.label(:sensor, i.to_s) }
              .update!
            offset += 4
          end

          fields_spec = [
            ["charge_rate",           4, 100.0],
            ["total_battery_voltage", 4, 100.0],
            ["residual_capacity",     4, 100.0],
            [nil,                     2],
            ["battery_capacity",      4, 100.0],
            ["soc",                   4, 10.0],
            ["rated_capacity",        4, 100.0],
            ["cycles_count_total",    4, 1.0],
            ["soh",                   4, 10.0],
            ["port_voltage",          4, 100.0],
          ]
          attributes = {}
          fields_spec.each do |key, length, factor|
            next(offset += length) if key.nil? 

            hex_val = response[offset, length]
            value = hex_val.to_i(16)

            bytes = length / 2

            threshold = 1 << (bytes * 8 - 1)
            max_val   = 1 << (bytes * 8)
            value = value >= threshold ? value - max_val : value

            value = value.to_f / factor if factor != 1.0
            m(key, value).update!
            offset += length
          end
        end
      end
    end
  end
end

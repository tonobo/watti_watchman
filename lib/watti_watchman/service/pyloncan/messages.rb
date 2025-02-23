module WattiWatchman
  module Service
    class Pyloncan
      module Messages
        extend Pyloncan::CANSpec
        # standard frame, communication rate: 500kbps, data transmission cycle: 1s

        message do
          name "battery_charge_parameters"
          can_id 0x351

          value(:battery_charge_voltage,  area: [0,1], type: :uint16, scale: 10.0, unit: "V")
          value(:charge_current_limit,    area: [2,3], type: :int16,  scale: 10.0, unit: "A")
          value(:discharge_current_limit, area: [4,5], type: :int16,  scale: 10.0, unit: "A")
          value(:discharge_voltage_limit, area: [6,7], type: :uint16, scale: 10.0, unit: "V")
        end

        message do
          name "battery_soc_and_battery_soh"
          can_id 0x355

          value(:state_of_charge, area: [0,1], type: :uint16, unit: "%")
          value(:state_of_health, area: [2,3], type: :uint16, unit: "%")
        end

        message do
          name "battery_voltage_current_and_temp"
          can_id 0x356

          value(:battery_voltage, area: [0,1], type: :int16, scale: 100.0, unit: "V")
          value(:battery_current, area: [2,3], type: :int16, scale: 10.0, unit: "A")
          value(:battery_temp,    area: [4,5], type: :int16, scale: 10.0, unit: "°C")
        end

        message do
          name "system_status"
          can_id 0x359

          value(:protection_high_voltage,           area: 0, type: 'bitmask|1')
          value(:protection_low_voltage,            area: 0, type: 'bitmask|2')
          value(:protection_high_temp,              area: 0, type: 'bitmask|3')
          value(:protection_low_temp,               area: 0, type: 'bitmask|4')
          value(:protection_discharge_over_current, area: 0, type: 'bitmask|7')
          value(:protection_charge_over_current,    area: 1, type: 'bitmask|0')

          value(:warning_high_voltage,                    area: 2, type: 'bitmask|1')
          value(:warning_low_voltage,                     area: 2, type: 'bitmask|2')
          value(:warning_high_temp,                       area: 2, type: 'bitmask|3')
          value(:warning_low_temp,                        area: 2, type: 'bitmask|4')
          value(:warning_discharge_over_current,          area: 2, type: 'bitmask|7')
          value(:warning_charge_over_current,             area: 3, type: 'bitmask|0')
          value(:warning_internal_communication_failure,  area: 3, type: 'bitmask|3')
          value(:warning_cell_failure,                    area: 3, type: 'bitmask|4')
        end

        message do
          name "bms_status"
          can_id 0x35C

          value(:charge_enable,           area: 0, type: 'bitmask|7')
          value(:discharge_enable,        area: 0, type: 'bitmask|6')

          # designed for inverter allows battery to shut down, and able to wake battery up to charge it
          value(:request_force_charge_1,  area: 0, type: 'bitmask|5')

          # designed for inverter doesn`t want battery to shut down, able to charge battery before shut down to
          # avoid low energy. We suggest inverter to use this bit,
          # In this case, inverter itself should set a threshold of SOC: after force charge, only when battery SOC is higher
          # than this threshold then inverter will allow discharge, 
          # to avoid force charge and discharge status change frequently
          value(:request_force_charge_2,  area: 0, type: 'bitmask|4')
        end

        message do
          name "vendor_name"
          can_id 0x35E

          value(:vendor_name, area: (0..7).to_a, type: :ASCII)
        end

        message do
          name "battery_cell_status"
          can_id 0x370

          value(:max_cell_temp,     area: [0,1], type: :int16, scale: 10.0, unit: "°C")
          value(:min_cell_temp,     area: [2,3], type: :int16, scale: 10.0, unit: "°C")
          value(:max_cell_voltage,  area: [4,5], type: :int16, scale: 1000.0, unit: "V")
          value(:min_cell_voltage,  area: [6,7], type: :int16, scale: 1000.0, unit: "V")
        end
      end
    end
  end
end

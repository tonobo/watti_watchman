require_relative './request'

module WattiWatchman
  class Meter
    class Seplos
      class SettingsRequest < Seplos::Request
        attr_reader :bms

        def initialize(bms:)
          @bms = bms
          super(function: 0x47)
        end

        def m(name, value=0, haklass: "-", unit: "-")
          Metric.new(
            Definition.new("seplos_settings_"+name, unit, "measurement", haklass, "-"),
            value
          ).tap do |metric|
            metric.origin(self)
            metric.label(:bms, bms.name)
          end
        end

        def boolvalue(val)
          raise ArgumentError, "this is only for true or false values" unless [true, false].include?(val)

          return 1 if val
          return 0
        end

        def self.int_paras
          @int_paras ||= Seplos.xml
            .locate("*/protocolConfig/int_para_Group/int_para")
            .map do 
              [
                _1.locate('Name/*'), 
                _1.locate('ParaIndex/*'), 
                _1.locate('ByteNum/*'), 
                _1.locate('Scale/*'),
                _1.locate('UnitName/*')
              ].flatten
            end.map do
              unit_scale_and_hafix({
                name: _1[0], 
                byte_index: _1[1].to_i(16), 
                byte_num: _1[2].to_i, 
                scale: _1[3].to_f,
                unit: _1[4]
              })
            end
        end

        def self.unit_scale_and_hafix(spec)
          case spec[:unit]
          when "℃"
            spec[:unit] = "°C"
            spec[:calc] = ->(val) { (val + 2731) * spec[:scale] }
            spec[:haklass] = "temperature"
          when "V"
            spec[:haklass] = "voltage"
          when "A"
            spec[:haklass] = "current"
          when "Ah"
            spec[:haklass] = "energy" # maybe
          when "%"
            spec[:haklass] = "battery"
          when "mS", "Minutes"
            spec[:haklass] = "duration"
          when "mΩ"
            spec[:haklass] = "-"
          else 
            spec[:haklass] = "-"
            spec[:unit] = "-"
          end
          spec[:name] = spec[:name].tr(" ", "_").downcase
          spec[:calc] ||= ->(val) { val * spec[:scale] }
          spec
        end 

        def self.bit_paras
          @bit_paras ||= Seplos.xml
            .locate("*/protocolConfig/bit_para_Group/bit_para")
            .map do 
              [
                _1.locate('Name/*'), 
                _1.locate('ByteIndex/*'), 
                _1.locate('BitIndex/*')
              ].flatten
            end.map do
              { 
                name: _1[0].tr(" ", "_").downcase, 
                byte_index: _1[1].to_i(16), 
                bit_index: _1[2].to_i
              }
            end
        end

        def process(response)
          data_bytes = [response[12..-1]].pack("H*")
          offset = 2

          results = {values: {}, switches: {}}
          self.class.int_paras.each do |param|
            value = 0
            param[:byte_num].times do |i|
              value <<= 8
              value |= data_bytes[offset, param[:byte_num]].getbyte(i)
            end
            m(
              "value_#{param[:name]}", 
              param[:calc].call(value),
              haklass: param[:haklass],
              unit: param[:unit]
            ).tap{ _1.label(:unit, param[:unit]) }.update!
            offset += param[:byte_num]
          end

          offset += 2
          self.class.bit_paras.each do |bp|
            byte = data_bytes[offset..-1].getbyte(bp[:byte_index])
            bit = (byte >> bp[:bit_index]) & 0x1
            m("switch_#{bp[:name]}", boolvalue(bit == 1)).update!
          end
        end
      end
    end
  end
end

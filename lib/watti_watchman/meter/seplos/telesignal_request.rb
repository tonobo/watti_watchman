require_relative './request'

module WattiWatchman
  class Meter
    class Seplos
      class TelesignalRequest < Seplos::Request
        class UnexpectedTempSensorCountError < Error; end

        attr_reader :bms

        def initialize(bms:)
          @bms = bms
          super(function: 0x44)
        end

        def m(name, value=0)
          name = name.gsub(/[^A-Za-z0-9]/, "_").downcase 
          Metric.new(
            Definition.new("seplos_telesignal_"+name, "-", "measurement", "-", "-"),
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

        def self.telesignal_block
          @teleSignal_block ||= Seplos.xml.locate("*/protocolConfig/teleSignal_Group/teleSignal_block")
        end

        def process(response)
          data_bytes = [response[12..-1]].pack("H*")

          offset = 2
          number_of_cells = data_bytes.getbyte(offset); offset += 1
          gbstates = [:cell_protect, :temp_protect, :charge_protect]
          self.class.telesignal_block.map do |block|
            byte_num_adjust = block.locate("ByteNumAdjust/*").first.to_i
            signal_type =  block.locate("SignalType/*").first
            case signal_type
            when 'GB_Byte'
              state = gbstates.shift
              if state == :cell_protect
                number_of_cells.times do |i|
                  byte = data_bytes.getbyte(offset)
                  m("voltage_warn_cell_#{i+1}", byte).update!
                  offset += 1
                end
                number_of_tempsensors = data_bytes.getbyte(offset)
                if number_of_tempsensors != 6
                  raise UnexpectedTempSensorCountError, "temp sensors should equal 6"
                end
                offset += 1
              else
                block.locate("teleSignalGB").each do |entry|
                  name = entry.locate("Name/*").flatten.join("_").tr(" ", "_").downcase 
                  type = entry.locate("Type/*").flatten.join("_").tr(" ", "_").downcase
                  byte = data_bytes.getbyte(offset)
                  m(name, byte).tap{ _1.label(:type, type) }.update!
                  offset += 1
                end
              end
            when 'Ext_Bit'
              offset += 1
              block.locate("teleSignal").each do |entry|
                name = entry.locate("Name/*").flatten.join("_").tr(" ", "_").downcase 
                type = entry.locate("Type/*").flatten.join("_").tr(" ", "_").downcase
                byte_index = entry.locate("ByteIndex/*").first.to_i
                bit_index = entry.locate("BitIndex/*").first.to_i
                byte = data_bytes.getbyte(offset + byte_index)
                flag = byte & (1 << bit_index) != 0
                m(name, boolvalue(flag)).tap{ _1.label(:type, type) }.update!
              end
            when 'Mode_Byte'
              block.locate("modeText").each do |entry|
                name = (["system_power_status"] + entry.locate("text/*")).flatten.join("_").tr(" ", "_").downcase
                byte_index = entry.locate("ByteIndex/*").first.to_i
                value = entry.locate("value/*").first.to_i
                byte = data_bytes.getbyte(offset + byte_index)
                flag = byte == value
                m(name, boolvalue(flag)).update!
              end
            end
          end
        end
      end
    end
  end
end

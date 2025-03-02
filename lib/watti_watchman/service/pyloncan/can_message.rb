module WattiWatchman
  module Service
    class Pyloncan
      module CANMessage
        def name(arg)
          raise(ArgumentError, "name must be given") unless arg.is_a?(String)
          _avoid_override(arg)
          @name = arg
        end

        def can_id(arg)
          raise(ArgumentError, "can_id must be an int") unless arg.is_a?(Integer)
          _avoid_override(arg)
          @can_id = arg
        end

        def value(name, area: nil, type:, scale: 1.0, unit: nil)
          @values ||= {}
          area = [area].flatten
          @values[name] = {
            area: area,
            type: type,
            scale: scale,
            unit: nil,
            parse_cb: _value_parse_cb(area, type, scale)
          }
        end

        private

        def _attributes
          {
            box: self,
            name: @name,
            can_id: @can_id,
            values: @values,
          }
        end

        def _value_parse_cb(area, type, scale)
          lambda do |data|
            case type.to_s
            when 'ASCII'
              data[area.first..area.last].map{ _1.chr }.join 
            when /bitmask\|[0-7]/
              bit = type.to_s[/bitmask\|(\d)/, 1].to_i
              (data[area.first] & (1 << bit)) != 0
            when 'uint16'
              raise(ArgumentError, "area #{area} must match 2 bytes") unless area.size == 2
              (data[area.first] | (data[area.last] << 8)) / scale
            when 'int16'
              raise(ArgumentError, "area #{area} must match 2 bytes") unless area.size == 2
              (data[area.first] | (data[area.last] << 8)).yield_self do
                _1 >= 0x8000 ? (_1 - 0x10000) / scale : _1 / scale
              end 
            else
              raise(ArgumentError, "type #{type} not supported")
            end
          end
        end

        def _avoid_override(val)
          return unless val.nil?

          raise(ArgumentError, "cannot override the same attribute within the same context")
        end
      end
    end
  end
end

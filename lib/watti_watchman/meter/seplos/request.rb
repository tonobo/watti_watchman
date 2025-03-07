module WattiWatchman
  class Meter
    class Seplos
      class Request
        include WattiWatchman::Logger

        DEFAULT = {
          data: "00",
        }

        attr_reader :options
        attr_accessor :timeout, :enqueued_at, :addr

        def initialize(function:, **options)
          @options = DEFAULT.merge(options)
          @options[:function] = function
        end

        def expired?
          raise(ArgumentError, "enqueued_at must not be nil") if enqueued_at.nil? 
          raise(ArgumentError, "timout must not be nil") if timeout.nil? 

          deadline = (enqueued_at + timeout)
          WattiWatchman.now > deadline
        end

        def type
          self.class.name.split("::").last.gsub(/([^\^])([A-Z])/,'\1_\2').downcase
        end

        def data
          encode_cmd(addr, options[:function])
        end

        def process(request)
          raise ArgumentError, 'this method should be implemented by child class'
        end

        private

        def calculate_frame_checksum(frame)
          checksum = 0
          frame.each_byte { |b| checksum += b }
          checksum %= 0xFFFF
          checksum ^= 0xFFFF
          checksum += 1
          checksum
        end

        def self.inverse_info_length(hex_str)
          num = hex_str.to_i(16)
          return 0 if num == 0

          lenid  = num & 0xFFF
          chksum = (num >> 12) & 0xF

          expected = ((((lenid & 0xF) +
                        ((lenid >> 4) & 0xF) +
                        ((lenid >> 8) & 0xF)) % 16) ^ 0xF) + 1

          unless expected == chksum
            raise "invalid checksum: expected=#{expected}, got=#{chksum}"
          end

          lenid
        end

        def info_length(info)
          lenid = info.bytesize
          return 0 if lenid == 0

          lchksum = (lenid & 0xF) + ((lenid >> 4) & 0xF) + ((lenid >> 8) & 0xF)
          lchksum %= 16
          lchksum ^= 0xF
          lchksum += 1
          (lchksum << 12) + lenid
        end

        def encode_cmd(address, cid2 = nil, info = "01".b)
          cid1 = 0x46
          info_length = info_length(info)
          frame = format("%02X%02X%02X%02X%04X", 0x20, address, cid1, cid2 || 0x00, info_length).b
          frame += info
          checksum = calculate_frame_checksum(frame)
          encoded = frame + format("%04X", checksum).b
          encoded
        end
      end
    end
  end
end

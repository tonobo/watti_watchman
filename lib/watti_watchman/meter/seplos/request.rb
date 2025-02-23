module WattiWatchman
  class Meter
    class Seplos
      class Request
        include WattiWatchman::Logger

        DEFAULT = {
          version: 0x20,
          address: 0,
          device_code: 0x46,
          data: "00",
        }

        attr_reader :options
        attr_accessor :timeout, :enqueued_at

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
          base = header + lchksum(options[:data]) + options[:data]
          base + chksum(base)
        end

        def process(request)
          raise ArgumentError, 'this method should be implemented by child class'
        end

        private

        def header
          "%02X%02X%02X%02X" % [
            options[:version],
            options[:address],
            options[:device_code],
            options[:function],
          ]
        end

        def chksum(data)
          sum = data.bytes.reduce(0) { |sum, byte| sum + byte }
          sum = (~sum) + 1
          '%X' % ((sum % 0xFFFF) + 1)
        end

        def lchksum(data)
          len = data.size
          lsum = (len & 0xf) + ((len >> 4) & 0xf) + ((len >> 8) & 0xf)
          lsum = ~(lsum % 16) + 1
          '%X' % (((lsum << 12) + len) & 0xFFFF)
        end
      end
    end
  end
end

require 'ffi'

module WattiWatchman
  module Service
    class Pyloncan
      class CANError < Error; end

      include WattiWatchman::Logger
      extend WattiWatchman::Config::Hooks

      service_config "Pyloncan" do |config, item|
        can = WattiWatchman::Service::Pyloncan.new(
          interface: item["interface"],
        )
        can.spawn
      end

      attr_reader :interface

      def initialize(interface:)
        @interface = interface
      end

      def parse_message(can_id, data)
        return unless self.class.messages[can_id]

        self.class.messages[can_id].fetch(:values).to_h do |name, v|
          [name, v.fetch(:parse_cb).call(data)] 
        rescue StandardError => err
          logger.warn("failed to parse can message 0x#{can_id.to_s(16).upcase} "\
                      "(#{name}): #{err}")
        end
      end

      def spawn
        @read_loop ||= Thread.new do
          can_sock = CANFFI.socket(CANFFI::AF_CAN, CANFFI::SOCK_RAW, CANFFI::CAN_RAW)
          CANFFI.raise_if_error(can_sock, "unable to create socketcan connection")

          if_index = CANFFI.if_nametoindex(interface)
          if if_index == 0
            raise CANError, "unable to find can interface for #{interface.inspect}"
          end

          sockaddr_can = CANFFI::SockAddrCAN.new
          sockaddr_can[:can_family] = CANFFI::AF_CAN
          sockaddr_can[:can_ifindex] = if_index

          ret = CANFFI.bind(can_sock, sockaddr_can.pointer, sockaddr_can.size)
          CANFFI.raise_if_error(ret, "unable to bind on #{interface.inspect}")

          loop do
            can_frame = CANFFI::CanFrame.new
            bytes_received = CANFFI.recv(can_sock, can_frame.pointer, CANFFI::CanFrame.size, 0)

            if bytes_received > 0
              can_id = can_frame[:can_id] & 0x1FFFFFFF
              dlc = can_frame[:can_dlc]
              data = can_frame[:data].to_a[0, dlc]

              puts "0x#{can_id.to_s(16)} #{data.map { |b| sprintf('%02X', b) }.join(' ')}"
              puts parse_message(can_id, data).to_json
              puts "-----------------------"
            end
            sleep 0.01
          end

        ensure
          CANFFI.close(can_sock)
        end
      end

      def self.messages
        @messages ||= {}
      end
    end
  end
end

require_relative "./pyloncan/canffi"
require_relative "./pyloncan/can_message"
require_relative "./pyloncan/can_spec"
require_relative "./pyloncan/messages"

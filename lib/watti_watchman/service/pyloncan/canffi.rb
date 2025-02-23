require 'ffi'

module WattiWatchman
  module Service
    class Pyloncan
      module CANFFI
        extend FFI::Library

        ffi_lib FFI::Library::LIBC

        PF_CAN = 29
        AF_CAN = PF_CAN
        SOCK_RAW = 3
        CAN_RAW = 1
        SOL_CAN_BASE = 100
        CAN_RAW_FILTER = 1

        class SockAddrCAN < FFI::Struct
          layout(
            :can_family, :ushort,
            :can_ifindex, :int
          )
        end

        class CanFrame < FFI::Struct
          layout(
            :can_id, :uint,
            :can_dlc, :uchar,
            :__pad, :uchar,
            :__res0, :uchar,
            :__res1, :uchar,
            :data, [:uchar, 8]
          )
        end

        attach_function :socket, [:int, :int, :int], :int
        attach_function :bind, [:int, :pointer, :uint], :int
        attach_function :recv, [:int, :pointer, :size_t, :int], :ssize_t
        attach_function :send, [:int, :pointer, :size_t, :int], :ssize_t
        attach_function :if_nametoindex, [:string], :uint
        attach_function :close, [:int], :int
        attach_function :strerror, [:int], :string

        def self.raise_if_error(ret, message)
          return unless ret == -1

          raise CANError, "#{message}: #{CAN.stderror(FFI.errno)}"
        end
      end
    end
  end
end


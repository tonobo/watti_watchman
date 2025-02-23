require 'socket'

module WattiWatchman
  module Internal
    class NonBlockingTCPClient
      attr_reader :write_timeout, :read_timeout

      def initialize(host, port, write_timeout: 5, read_timeout:5)
        @write_timeout = write_timeout
        @read_timeout = read_timeout
        @socket = TCPSocket.new(host, port)
        @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      end

      def write(data)
        raise "Socket closed" if @socket.closed?

        if @socket.wait_writable(write_timeout)
          @socket.write(data)
        else
          raise "Write timeout after #{write_timeout} seconds"
        end
      end

      def read(max_bytes = 1024)
        raise "Socket closed" if @socket.closed?

        if @socket.wait_readable(read_timeout)
          return @socket.read_nonblock(max_bytes)
        else
          raise "Read timeout after #{read_timeout} seconds"
        end
      rescue IO::WaitReadable, EOFError, Errno::EAGAIN
        return nil
      end

      def close
        @socket.close unless @socket.closed?
      end
    end
  end
end

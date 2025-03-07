require_relative '../internal/non_blocking_tcp_client'
require 'ox'

module WattiWatchman
  class Meter
    class Seplos
      require_relative './seplos/telemetry_request.rb'
      require_relative './seplos/telesignal_request.rb'
      require_relative './seplos/settings_request.rb'
      require_relative './seplos/interpack_frame.rb'

      class InvalidRequestError < Error; end

      include WattiWatchman::Logger
      extend WattiWatchman::Config::Hooks

      meter_config "Seplos" do |config, item|
        meter = WattiWatchman::Meter::Seplos.new(
          name: item["name"],
          host: item["host"],
          port: item["port"],
          addr: item["addr"] || 0,
        )
        meter.spawn
        WattiWatchman::Meter.connections[item['name']] = meter
      end
      
      Metrics = [
        %w(request_duration_seconds_total   s  total_increasing  - -),
        %w(request_count_total              -  total_increasing  - -),
        %w(request_count_expired_total      -  total_increasing  - -),
        %w(request_errors_count_total       -  total_increasing  - -),
        %w(client_reset_count_total         -  total_increasing  - -),
      ].to_h{ [_1[0], Definition.new("seplos_#{_1[0]}", *_1[1..-1]) ]}

      INTERVAL = 0.5

      attr_reader :name, :host, :port, :addr, :interval

      def self.xml
        @addr ||= Ox.parse(File.read(
          File.join(
            File.dirname(File.expand_path(__FILE__)),
            "seplos/addr.xml"
          )
        ))
      end

      def initialize(name:, host:, port:, addr:, interval: INTERVAL)
        @name = name
        @host = host
        @port = port
        @interval = interval
        @addr = addr

        @request_queue = Queue.new
        @response_queue = Queue.new
      end

      def q(klass, timeout: INTERVAL)
        unless klass.is_a?(Class)
          raise(InvalidRequestError, "#{klass} must be a Class")
        end

        unless klass < Seplos::Request
          raise(InvalidRequestError, "#{klass} must inherited from Seplos::Request")
        end

        if timeout > interval
          raise(InvalidRequestError, "timeout(#{timeout}) must be lte interval(#{interval})")
        end

        unless connected? 
          logger.warn "skip enqueing of request '#{klass}', not yet connected"
          return
        end

        request = klass.new(bms: self)
        request.timeout = timeout
        request.enqueued_at = WattiWatchman.now
        request.addr = addr
        request.tap { @request_queue << _1 }
      end

      def m(name)
        Metric.new(Metrics[name], 0.0).tap do |metric|
          metric.origin(self)
          metric.label(:bms, self.name)
        end
      end

      def enqueue_loop 
        @enqueue_loop ||= Thread.new do
          loop do
            sleep 1
            # settings request is not supported in clustered mode
            # q(WattiWatchman::Meter::Seplos::SettingsRequest)
            #
            #q(WattiWatchman::Meter::Seplos::TelemetryRequest)
            #q(WattiWatchman::Meter::Seplos::TelesignalRequest)
          rescue StandardError => err
            logger.warn "failed to enqueue requests: #{err}"
          end
        end
      end

      def spawn
        enqueue_loop
        @spawn ||= Thread.new do
          loop do
            process_loop
          rescue StandardError => err
            logger.error "caught error: #{err}, resetting connection"
            logger.error err
            m("client_reset_count_total").increment!
            sleep 1
          end
        end
      end

      def connected?
        @connected == true
      end

      def read_loop(socket)
        Thread.new do
          loop do
            response = ""
            loop do
              char = socket.read(1)
              unless char[/\A[0-9a-f~\r]\z/i]
                response = ""
                next
              end
              response << char
              if char == "\r"
                break
              end
            end
            begin
              parsed_response = response.strip.sub(/^~/, '').sub(/\r$/, '')
              result = [parsed_response].pack('H*')
              r = "response: #{parsed_response}"
              case result.getbyte(3)
              when 0x00 then nil # normal
              when 0x01 then next(logger.warn("#{r}: version abnormal"))
              when 0x02 then next(logger.warn("#{r}: checksum abnormal"))
              when 0x03 then next(logger.warn("#{r}: lchecksum abnormal"))
              when 0x04 then next(logger.warn("#{r}: invalid cid2"))
              when 0x05 then next(logger.warn("#{r}: invalid command"))
              when 0x06 then next(logger.warn("#{r}: invalid data"))
              when 0x07 then next(logger.warn("#{r}: no data"))
              when 0xE1 then next(logger.warn("#{r}: invalid cid1"))
              when 0xE2 then next(logger.warn("#{r}: command execution failed"))
              when 0xE3 then next(logger.warn("#{r}: equipment failure"))
              when 0xE4 then next(logger.warn("#{r}: no permisson"))
              when 0x5A
                # skip if request is unparseable
                len = (Seplos::Request.inverse_info_length(result[4,2].unpack("H*")[0]) rescue next)
                next if len == 0 # request for inter pack frame
                next Seplos::InterpackFrame.new(bms: self).process(parsed_response)
              else
                next(logger.warn("#{r}: unable to handle response"))
              end
              @response_queue << parsed_response
            rescue StandardError => err
              logger.error "failed to process response: #{response}\n#{err}#\n#{err.backtrace.join("\n")}"
            end
          end
        end
      end

      def process_loop
        error_counter = 0
        socket = TCPSocket.new(host, port)
        socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        logger.info "connected to #{host}:#{port}"
        @connected = true
        rl = read_loop(socket)
        loop do 
          request = @request_queue.pop
          started_at = WattiWatchman.now
          m("request_count_total").tap{ _1.label(:request, request.type) }.increment!

          if request.expired?
            m("request_count_expired_total").tap{ _1.label(:request, request.type) }.increment!
            next
          end
          logger.debug "request write: #{request.data}"
          socket.write("~#{request.data}\r")
          response = @response_queue.pop(timeout: 5)
          raise("response timeout, resetting connection") if response.nil?
          request.process(response)
        end
      ensure
        rl&.kill rescue nil
        socket.close rescue nil
        @connected = false
      end
    end
  end
end

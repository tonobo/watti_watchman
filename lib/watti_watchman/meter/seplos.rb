require_relative '../internal/non_blocking_tcp_client'
require 'ox'

module WattiWatchman
  class Meter
    class Seplos
      require_relative './seplos/telemetry_request.rb'
      require_relative './seplos/telesignal_request.rb'
      require_relative './seplos/settings_request.rb'

      class InvalidRequestError < Error; end

      include WattiWatchman::Logger
      extend WattiWatchman::Config::Hooks

      meter_config "Seplos" do |config, item|
        meter = WattiWatchman::Meter::Seplos.new(
          name: item["name"],
          host: item["host"],
          port: item["port"],
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

      attr_reader :name, :host, :port, :interval

      def self.xml
        @addr ||= Ox.parse(File.read(
          File.join(
            File.dirname(File.expand_path(__FILE__)),
            "seplos/addr.xml"
          )
        ))
      end

      def initialize(name:, host:, port:, interval: INTERVAL)
        @name = name
        @host = host
        @port = port
        @interval = interval

        @request_queue = Queue.new
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
            q(WattiWatchman::Meter::Seplos::SettingsRequest)
            q(WattiWatchman::Meter::Seplos::TelemetryRequest)
            q(WattiWatchman::Meter::Seplos::TelesignalRequest)
          rescue StandardError => err
            logger.warn "failed to enqueue requests: #{err}"
          end
        end
      end

      def spawn
        @spawn ||= Thread.new do
          enqueue_loop
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

      def process_loop
        error_counter = 0
        socket = Internal::NonBlockingTCPClient.new(host, port)
        @connected = true
        logger.info "connected to #{host}:#{port}"
        loop do 
          request = @request_queue.pop
          started_at = WattiWatchman.now
          m("request_count_total").tap{ _1.label(:request, request.type) }.increment!

          if request.expired?
            m("request_count_expired_total").tap{ _1.label(:request, request.type) }.increment!
            next
          end
          #logger.debug "requst: #{request.data}"
          socket.write("~#{request.data}\r")
          response = ""
          loop do
            char = socket.read(1)
            if char.nil?
              m("request_errors_count_total")
                .tap{ _1.label(:error, "read_error") }
                .tap{ _1.label(:request, request.type) }
                .increment!
              break
            end
            response << char
            if char == "\r"
              m("request_duration_seconds_total")
                .tap{ _1.label(:request, request.type) }
                .increment!(WattiWatchman.now - started_at)
              break
            end
          end
          begin
            parsed_response = response.strip.sub(/^~/, '').sub(/\r$/, '')
            #logger.debug "response: #{parsed_response}"
            request.process(parsed_response)
          rescue StandardError => err
            logger.error "failed to process response: #{response}\n#{err}#\n#{err.backtrace.join("\n")}"
          end
        end
      ensure
        @connected = false
      end
    end
  end
end

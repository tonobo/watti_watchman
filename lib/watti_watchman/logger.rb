module WattiWatchman
  module Logger
    class ThrottledLogger < ::Logger
      def initialize(logdev, shift_age = 0, shift_size = 1048576,
                     throttle_interval: 5, max_errors: 500)
        super(logdev, shift_age, shift_size)
        @throttle_interval = throttle_interval
        @max_errors = max_errors
        @last_logged_at = {}
      end

      def add(severity, message = nil, progname = nil, &block)
        msg = format_message_for_throttle(message, progname, &block)
        now = WattiWatchman.now

        return unless should_log?(msg, now)

        old_counter = @last_logged_at.dig(msg, :counter).to_i
        @last_logged_at[msg] = { time: now, counter: 0 }

        if @last_logged_at.size > @max_errors
          remove_oldest_entries(@last_logged_at.size - @max_errors)
        end

        if message
          message += " (suppressed #{old_counter - 1} logs)" if old_counter > 1 
        elsif progname.is_a?(String) && block.nil?
          progname += " (suppressed #{old_counter - 1} logs)" if old_counter > 1 
        end

        super(severity, message, progname, &block)
      end

      private

      def format_message_for_throttle(message, progname, &block)
        if message.nil?
          if block_given?
            message = block.call
          else
            message = progname
            progname = nil
          end
        end
        message.to_s
      end

      def should_log?(error_key, current_time)
        if @last_logged_at[error_key].to_h.key?(:counter)
          @last_logged_at[error_key][:counter] += 1
        end
        last_time = @last_logged_at.dig(error_key, :time).to_i
        (current_time - last_time) >= @throttle_interval
      end

      def remove_oldest_entries(count)
        oldest_keys = @last_logged_at.sort_by { |k, v| v[:time] }.map(&:first)
        oldest_keys.first(count).each { |key| @last_logged_at.delete(key) }
      end
    end

    def logger
      @logger ||= ThrottledLogger.new(STDERR).tap do
        _1.progname ||= case self.class.name
                        when "Module", "Class"
                          "#{name}"
                        else
                          "#{self.class.name}##{'%08d' % object_id}"
                        end
      end
    end
  end
end

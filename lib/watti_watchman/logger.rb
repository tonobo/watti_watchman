module WattiWatchman
  module Logger
    def logger
      @logger ||= ::Logger.new(STDERR).tap do
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

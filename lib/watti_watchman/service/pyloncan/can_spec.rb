module WattiWatchman
  module Service
    class Pyloncan
      module CANSpec
        def message(&block)
          raise(ArgumentError, "can message block cannot be empty") unless block_given?
          box = Class.new
          box.extend(CANMessage)
          box.instance_eval(&block)
          WattiWatchman::Service::Pyloncan
            .messages[box.instance_eval{ @can_id }] = box.instance_eval{ _attributes }
        end
      end
    end
  end
end

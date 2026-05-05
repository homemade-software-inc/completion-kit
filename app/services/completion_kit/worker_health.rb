module CompletionKit
  class WorkerHealth
    HEARTBEAT_THRESHOLD = 30.seconds

    def self.healthy?
      return true unless defined?(::SolidQueue::Process)
      ::SolidQueue::Process.where("last_heartbeat_at > ?", HEARTBEAT_THRESHOLD.ago).exists?
    end
  end
end

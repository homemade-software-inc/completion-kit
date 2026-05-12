module CompletionKit
  class WorkerHealth
    # SolidQueue workers heartbeat every SolidQueue.process_heartbeat_interval
    # (60s by default), so a 30s window flagged healthy workers as down between
    # beats. Allow two missed heartbeats before we say the worker is gone.
    HEARTBEAT_THRESHOLD = 2.minutes

    def self.healthy?
      return true unless defined?(::SolidQueue::Process)
      ::SolidQueue::Process
        .where("kind LIKE 'Worker%'")
        .where("last_heartbeat_at > ?", HEARTBEAT_THRESHOLD.ago)
        .exists?
    end
  end
end

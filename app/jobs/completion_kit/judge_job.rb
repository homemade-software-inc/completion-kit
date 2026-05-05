module CompletionKit
  class JudgeJob < ApplicationJob
    queue_as :default

    def perform(_run_id)
    end
  end
end

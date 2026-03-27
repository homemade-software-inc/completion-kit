module CompletionKit
  class JudgeJob < ApplicationJob
    queue_as :default

    def perform(run_id)
      run = Run.find_by(id: run_id)
      return unless run

      run.judge_responses!
    end
  end
end

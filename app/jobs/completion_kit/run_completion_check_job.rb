module CompletionKit
  class RunCompletionCheckJob < ApplicationJob
    queue_as :default

    def perform(run_id)
      run = Run.find_by(id: run_id)
      return unless run
      return unless run.status == "running"
      return unless run.outstanding_work_zero?

      run.mark_completed!
    end
  end
end

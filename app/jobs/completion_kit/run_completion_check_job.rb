module CompletionKit
  class RunCompletionCheckJob < ApplicationJob
    queue_as :default

    limits_concurrency to: 1,
                       key: ->(run_id) { "run:#{run_id}:completion" },
                       duration: 5.minutes

    def perform(run_id)
      run = Run.find_by(id: run_id)
      return unless run
      return unless run.status == "running"
      # A run that has been claimed but whose rows are still being inserted by
      # StartRunJob has no outstanding work yet, and would otherwise complete
      # itself with zero responses.
      return if run.progress_total.zero?
      return unless run.outstanding_work_zero?

      run.mark_completed!
    end
  end
end

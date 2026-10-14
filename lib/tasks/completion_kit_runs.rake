namespace :completion_kit do
  desc "Mark in-flight runs in every tenant as failed (for use after the queue adapter cutover)"
  task mark_interrupted_runs_failed: :environment do
    scope = CompletionKit::Run.unscoped.where(status: "running")
    count = scope.count
    scope.update_all(
      status: "failed",
      failure_summary: "Interrupted by deploy",
      updated_at: Time.current
    )
    puts "Marked #{count} runs as failed."
  end
end

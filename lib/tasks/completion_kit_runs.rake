namespace :completion_kit do
  desc "Mark in-flight runs as failed (for use after the queue adapter cutover)"
  task mark_interrupted_runs_failed: :environment do
    scope = CompletionKit::Run.where(status: "running")
    count = scope.count
    scope.update_all(
      status: "failed",
      failure_summary: "Interrupted by deploy",
      updated_at: Time.current
    )
    puts "Marked #{count} runs as failed."
  end
end

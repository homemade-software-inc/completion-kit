module RunStartHelper
  # start! now only claims the run and enqueues StartRunJob, so specs that want
  # the responses and row jobs must drain that job the way a worker would.
  def start_run!(run, scope_defaults = {})
    result = run.start!
    return result unless result

    # The job works through its own Run instance, so the caller's association
    # cache still reflects the empty run start! left behind.
    CompletionKit::StartRunJob.perform_now(run.id, scope_defaults)
    run.responses.reset
    run.reload
    result
  end
end

RSpec.configure do |config|
  config.include RunStartHelper
end

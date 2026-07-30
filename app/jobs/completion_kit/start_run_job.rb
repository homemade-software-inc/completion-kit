module CompletionKit
  class StartRunJob < ApplicationJob
    queue_as :default

    limits_concurrency to: 1,
                       key: ->(run_id, _defaults = {}) { "run:#{run_id}:start" },
                       duration: 10.minutes

    rescue_from(StandardError) do |error|
      Rails.error.report(error, handled: true, context: { job: self.class.name, run_id: @run_id })
      run = Run.find_by(id: @run_id)
      run&.fail_to_start!(error.message)
    end

    # scope_defaults carries the host's tenant columns, resolved in the web
    # request where the tenant context exists. A worker has no such context, so
    # without them the inserted responses would be stamped with nothing.
    def perform(run_id, scope_defaults = {})
      @run_id = run_id

      run = Run.find_by(id: run_id)
      return unless run
      return unless run.status == "running"
      return if run.responses.exists?

      run.execute_start!(scope_defaults.symbolize_keys)
    end
  end
end

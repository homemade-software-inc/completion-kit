module CompletionKit
  class GenerateJob < ApplicationJob
    queue_as :default

    def perform(run_id)
      run = Run.find_by(id: run_id)
      return unless run

      run.generate_responses!
    end
  end
end

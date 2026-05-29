RSpec.configure do |config|
  config.before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_status_header)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_actions)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_sort_toolbar)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_clear_responses)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_ui)
  end
end

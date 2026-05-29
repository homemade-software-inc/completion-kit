require "rails_helper"

RSpec.describe "model-driven Turbo broadcasts", type: :model do
  let(:run) { create(:completion_kit_run) }

  before do
    RSpec::Mocks.space.proxy_for(CompletionKit::Run.allocate).reset
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update).and_call_original
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress).and_call_original
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_replace_to)
  end

  it "Response.after_save_commit broadcasts the row when a Response is saved" do
    response = run.responses.build(status: "pending", row_index: 0)
    expect_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update).at_least(:once).and_call_original
    response.save!
  end

  it "Response.after_save_commit broadcasts progress only when status transitions to terminal" do
    response = run.responses.create!(status: "pending", row_index: 0)
    expect_any_instance_of(CompletionKit::Run).not_to receive(:broadcast_progress)
    response.update!(status: "retrying", attempts: 1)
  end

  it "Response.after_save_commit fires broadcast_progress when status moves to succeeded" do
    response = run.responses.create!(status: "pending", row_index: 0)
    expect_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress).at_least(:once)
    response.update!(status: "succeeded", response_text: "ok")
  end

  it "Review.after_save_commit broadcasts the parent response row and progress on terminal save" do
    response = run.responses.create!(status: "succeeded", response_text: "ok", row_index: 0)
    metric = create(:completion_kit_metric)
    expect_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update).at_least(:once).and_call_original
    expect_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress).at_least(:once)
    response.reviews.create!(metric: metric, metric_name: metric.name, status: "succeeded", ai_score: 4)
  end
end

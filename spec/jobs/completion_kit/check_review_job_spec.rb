require "rails_helper"

RSpec.describe CompletionKit::CheckReviewJob, type: :job do
  let(:metric) do
    create(:completion_kit_metric, :check,
           check_config: { "check_kind" => "contains", "target" => "response_text", "value" => "ok" })
  end
  let(:run) { create(:completion_kit_run) }
  let(:response) { create(:completion_kit_response, run: run, response_text: "all ok here") }

  before do
    CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
  end

  it "writes one succeeded review carrying passed, nil ai_score, and the detail in ai_feedback" do
    described_class.perform_now(response.id, metric.id, run.id)

    review = response.reviews.find_by(metric_id: metric.id)
    expect(response.reviews.count).to eq(1)
    expect(review.status).to eq("succeeded")
    expect(review.passed).to be(true)
    expect(review.ai_score).to be_nil
    expect(review.ai_feedback).to eq("contains \"ok\"")
    expect(review.metric_name).to eq(metric.name)
    expect(review.metric_version_id).to eq(CompletionKit::MetricVersion.ensure_current_for(metric).id)
  end

  it "records passed:false with a resolution detail when the target cannot be resolved" do
    metric.update!(check_config: { "check_kind" => "not_contains", "target" => "json_path", "target_path" => "a", "value" => "x" })
    response.update!(response_text: "not json at all")

    described_class.perform_now(response.id, metric.id, run.id)

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.status).to eq("succeeded")
    expect(review.passed).to be(false)
    expect(review.ai_feedback).to eq("could not resolve target")
  end

  it "records a genuine internal exception as failed and still enqueues the completion check" do
    allow(CompletionKit::Checks::Registry).to receive(:fetch).and_raise(RuntimeError, "boom")
    expect(CompletionKit::RunCompletionCheckJob).to receive(:perform_later).with(run.id)

    expect { described_class.perform_now(response.id, metric.id, run.id) }.not_to raise_error

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.status).to eq("failed")
    expect(review.metric_name).to eq(metric.name)
  end

  it "reuses the existing review row instead of creating a duplicate" do
    response.reviews.create!(metric: metric, metric_name: metric.name,
                             metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
                             status: "pending")

    expect { described_class.perform_now(response.id, metric.id, run.id) }
      .not_to change { response.reviews.count }
  end

  it "tail-calls RunCompletionCheckJob after a successful check" do
    expect(CompletionKit::RunCompletionCheckJob).to receive(:perform_later).with(run.id)
    described_class.perform_now(response.id, metric.id, run.id)
  end

  it "does not raise when the response row is missing and enqueues nothing" do
    expect(CompletionKit::RunCompletionCheckJob).not_to receive(:perform_later)
    expect { described_class.perform_now(0, metric.id, run.id) }.not_to raise_error
  end

  it "falls back to (deleted metric) name when the metric is gone on failure" do
    allow(CompletionKit::Checks::Registry).to receive(:fetch).and_raise(RuntimeError, "boom")
    metric_id = metric.id
    CompletionKit::RunMetric.where(metric_id: metric_id).delete_all
    metric.destroy!

    expect { described_class.perform_now(response.id, metric_id, run.id) }.not_to raise_error

    review = response.reviews.find_by(metric_id: metric_id)
    expect(review.metric_name).to eq("(deleted metric)")
  end

  it "keeps an existing review's metric_name on failure" do
    response.reviews.create!(metric: metric, metric_name: "Locked Name",
                             metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
                             status: "pending")
    job = described_class.new
    job.instance_variable_set(:@response_id, response.id)
    job.instance_variable_set(:@metric_id, metric.id)

    job.send(:record_terminal_failure!, RuntimeError.new("boom"))

    expect(response.reviews.find_by(metric_id: metric.id).metric_name).to eq("Locked Name")
  end
end

require "rails_helper"
require "faraday"

module CompletionKit
  class RunCompletionCheckJob < ApplicationJob
    def perform(*); end
  end unless defined?(RunCompletionCheckJob)
end

RSpec.describe CompletionKit::JudgeReviewJob, type: :job do
  let(:run) { create(:completion_kit_run, judge_model: "gpt-4o") }
  let(:metric) { create(:completion_kit_metric, name: "Quality") }
  let(:response) { create(:completion_kit_response, run: run, response_text: "answer") }

  before do
    CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
    allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
  end

  it "creates a Review with succeeded status on a successful evaluation" do
    fake_judge = double("judge", evaluate: { score: 4, feedback: "good" })
    allow(CompletionKit::JudgeService).to receive(:new).and_return(fake_judge)
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})

    described_class.perform_now(response.id, metric.id)

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.status).to eq("succeeded")
    expect(review.ai_score).to eq(4)
    expect(review.ai_feedback).to eq("good")
    expect(review.metric_name).to eq("Quality")
  end

  it "records terminal failure context" do
    allow_any_instance_of(described_class).to receive(:perform).and_raise(
      CompletionKit::RateLimitError.new("limit", provider: "anthropic", status: 429)
    )

    expect { described_class.perform_now(response.id, metric.id) }.not_to raise_error

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.status).to eq("failed")
    expect(review.error_class).to eq("CompletionKit::RateLimitError")
    expect(review.error_status).to eq(429)
  end

  it "enqueues RunCompletionCheckJob with the run_id" do
    fake_judge = double("judge", evaluate: { score: 4, feedback: "ok" })
    allow(CompletionKit::JudgeService).to receive(:new).and_return(fake_judge)
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})

    expect(CompletionKit::RunCompletionCheckJob).to receive(:perform_later).with(run.id)

    described_class.perform_now(response.id, metric.id)
  end

  it "reuses an existing Review row instead of creating a duplicate" do
    fake_judge = double("judge", evaluate: { score: 5, feedback: "great" })
    allow(CompletionKit::JudgeService).to receive(:new).and_return(fake_judge)
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})

    response.reviews.create!(metric: metric, metric_name: metric.name, status: "failed",
                              error_provider: "anthropic", error_class: "Stale",
                              error_message: "previous failure")

    expect {
      described_class.perform_now(response.id, metric.id)
    }.not_to change { response.reviews.count }

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.status).to eq("succeeded")
    expect(review.ai_score).to eq(5)
    expect(review.error_class).to be_nil
  end

  it "skips before_perform update when response does not exist" do
    expect { described_class.perform_now(0, metric.id) }.not_to raise_error
  end

  it "records terminal failure for errors without a status method" do
    plain_error = RuntimeError.new("something went wrong")
    allow_any_instance_of(described_class).to receive(:perform).and_raise(plain_error)

    expect {
      described_class.perform_now(response.id, metric.id)
    }.not_to raise_error

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.status).to eq("failed")
    expect(review.error_status).to be_nil
    expect(review.error_class).to eq("RuntimeError")
  end

  it "does not raise when response_id is missing during terminal failure" do
    allow_any_instance_of(described_class).to receive(:perform).and_raise(RuntimeError, "boom")

    expect {
      described_class.perform_now(0, metric.id)
    }.not_to raise_error
  end

  it "returns nil from provider_for when run has no judge_model" do
    run.update_column(:judge_model, nil)
    job = described_class.new
    expect(job.send(:provider_for, response)).to be_nil
  end

  it "does not enqueue RunCompletionCheckJob when response is missing in enqueue_completion_check" do
    job = described_class.new
    job.instance_variable_set(:@response_id, 0)
    expect(CompletionKit::RunCompletionCheckJob).not_to receive(:perform_later)
    job.send(:enqueue_completion_check)
  end

  it "rate limit wait is 30 seconds times the execution count" do
    expect(described_class.rate_limit_wait(3)).to eq(90)
    expect(described_class.rate_limit_wait(1)).to eq(30)
  end

  it "uses metric name from deleted metric in record_terminal_failure!" do
    allow_any_instance_of(described_class).to receive(:perform).and_raise(RuntimeError, "boom")
    allow(CompletionKit::Metric).to receive(:find_by).with(id: metric.id).and_return(nil)

    expect {
      described_class.perform_now(response.id, metric.id)
    }.not_to raise_error

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.metric_name).to eq("(deleted metric)")
  end

  it "skips broadcast in record_terminal_failure! when response has no run" do
    allow_any_instance_of(described_class).to receive(:perform).and_raise(RuntimeError, "boom")
    allow(response).to receive(:run).and_return(nil)
    allow(CompletionKit::Response).to receive(:find_by).with(id: response.id).and_return(response)

    expect { described_class.perform_now(response.id, metric.id) }.not_to raise_error
  end

  it "resolves metric name via Metric.find_by in record_terminal_failure! when review has no metric_name yet" do
    job = described_class.new
    job.instance_variable_set(:@response_id, response.id)
    job.instance_variable_set(:@metric_id, metric.id)

    job.send(:record_terminal_failure!, RuntimeError.new("boom"))

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.metric_name).to eq("Quality")
    expect(review.status).to eq("failed")
  end

  it "falls back to (deleted metric) when Metric.find_by returns nil in record_terminal_failure! with no review" do
    job = described_class.new
    job.instance_variable_set(:@response_id, response.id)
    job.instance_variable_set(:@metric_id, metric.id)
    allow(CompletionKit::Metric).to receive(:find_by).with(id: metric.id).and_return(nil)

    job.send(:record_terminal_failure!, RuntimeError.new("boom"))

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.metric_name).to eq("(deleted metric)")
  end
end

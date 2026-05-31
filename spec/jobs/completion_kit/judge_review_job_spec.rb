require "rails_helper"
require "faraday"

RSpec.describe CompletionKit::JudgeReviewJob, type: :job do
  let(:run) { create(:completion_kit_run, judge_model: "gpt-4o") }
  let(:metric) { create(:completion_kit_metric, name: "Quality") }
  let(:response) { create(:completion_kit_response, run: run, response_text: "answer") }

  before do
    CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
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

  it "evaluates a judge-only response (no prompt template) without blowing up" do
    judge_only = create(:completion_kit_run,
                        prompt: nil,
                        dataset: create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n"),
                        judge_model: "gpt-4o",
                        output_column: "actual_output")
    CompletionKit::RunMetric.create!(run: judge_only, metric: metric, position: 1)
    bare_response = create(:completion_kit_response, run: judge_only, response_text: "hello")

    captured_prompt = :unset
    fake_judge = double("judge")
    allow(CompletionKit::JudgeService).to receive(:new).and_return(fake_judge)
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})
    allow(fake_judge).to receive(:evaluate) do |_output, _expected, prompt, **_kw|
      captured_prompt = prompt
      {score: 3, feedback: "ok"}
    end

    described_class.perform_now(bare_response.id, metric.id)

    expect(captured_prompt).to be_nil
    expect(bare_response.reviews.find_by(metric_id: metric.id).status).to eq("succeeded")
  end

  it "records terminal failure context" do
    fake_judge = double("judge")
    allow(fake_judge).to receive(:evaluate).and_raise(
      CompletionKit::RateLimitError.new("limit", provider: "anthropic", status: 429)
    )
    allow(CompletionKit::JudgeService).to receive(:new).and_return(fake_judge)
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})

    expect { described_class.perform_now(response.id, metric.id) }.not_to raise_error

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.status).to eq("failed")
    expect(review.error_class).to eq("CompletionKit::RateLimitError")
    expect(review.error_status).to eq(429)
  end

  it "promotes an untested judge model to confirmed after a successful review" do
    model = create(:completion_kit_model, provider: "openai", model_id: "gpt-4o",
                   supports_generation: true, supports_judging: nil, judging_error: "stale",
                   status: "active")
    fake_judge = double("judge", evaluate: { score: 5, feedback: "ok" })
    allow(CompletionKit::JudgeService).to receive(:new).and_return(fake_judge)
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})

    described_class.perform_now(response.id, metric.id)

    expect(model.reload).to have_attributes(supports_judging: true, judging_error: nil)
  end

  it "leaves a model already flagged as a bad judge alone after a successful review" do
    model = create(:completion_kit_model, provider: "openai", model_id: "gpt-4o",
                   supports_generation: true, supports_judging: false, status: "active")
    fake_judge = double("judge", evaluate: { score: 5, feedback: "ok" })
    allow(CompletionKit::JudgeService).to receive(:new).and_return(fake_judge)
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})

    described_class.perform_now(response.id, metric.id)

    expect(model.reload.supports_judging).to be(false)
  end

  it "fails just that review (not the run) and does not touch the model when the judge raises" do
    model = create(:completion_kit_model, provider: "openai", model_id: "gpt-4o",
                   supports_generation: true, supports_judging: nil, status: "active")
    fake_judge = double("judge")
    allow(fake_judge).to receive(:evaluate).and_raise(RuntimeError, "judge melted down")
    allow(CompletionKit::JudgeService).to receive(:new).and_return(fake_judge)
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})

    expect { described_class.perform_now(response.id, metric.id) }.not_to raise_error

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.status).to eq("failed")
    expect(review.error_message).to include("judge melted down")
    expect(model.reload.supports_judging).to be_nil
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
                              error_message: "previous failure",
                              metric_version: CompletionKit::MetricVersion.ensure_current_for(metric))

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
    fake_judge = double("judge")
    allow(fake_judge).to receive(:evaluate).and_raise(RuntimeError, "something went wrong")
    allow(CompletionKit::JudgeService).to receive(:new).and_return(fake_judge)
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})

    expect {
      described_class.perform_now(response.id, metric.id)
    }.not_to raise_error

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.status).to eq("failed")
    expect(review.error_status).to be_nil
    expect(review.error_class).to eq("RuntimeError")
  end

  it "does not raise when response_id points at a missing row (Response.find blows up, rescue swallows it)" do
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

  it "concurrency key scopes to the run id via response lookup" do
    key_proc = described_class.concurrency_key
    allow(CompletionKit::Response).to receive(:find_by).with(id: response.id).and_return(response)
    expect(key_proc.call(response.id, metric.id)).to eq("run:#{run.id}")
  end

  it "concurrency key returns nil run_id when response not found" do
    key_proc = described_class.concurrency_key
    allow(CompletionKit::Response).to receive(:find_by).with(id: 0).and_return(nil)
    expect(key_proc.call(0, metric.id)).to eq("run:")
  end

  it "uses metric name from deleted metric in record_terminal_failure!" do
    fake_judge = double("judge")
    allow(fake_judge).to receive(:evaluate).and_raise(RuntimeError, "boom")
    allow(CompletionKit::JudgeService).to receive(:new).and_return(fake_judge)
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})
    allow(CompletionKit::Metric).to receive(:find_by).with(id: metric.id).and_return(nil)

    expect {
      described_class.perform_now(response.id, metric.id)
    }.not_to raise_error

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.metric_name).to eq("(deleted metric)")
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

  describe "review-grounded examples" do
    around do |example|
      original_examples = CompletionKit.config.judge_examples_from_reviews
      original_agreement = CompletionKit.config.judge_agreement_enabled
      example.run
    ensure
      CompletionKit.config.judge_examples_from_reviews = original_examples
      CompletionKit.config.judge_agreement_enabled = original_agreement
    end

    let(:run) { create(:completion_kit_run, judge_model: "gpt-4.1") }
    let(:response) { create(:completion_kit_response, run: run) }
    let(:metric) { create(:completion_kit_metric) }

    before do
      allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})
    end

    it "passes human_examples to the judge when the flag is on" do
      CompletionKit.config.judge_examples_from_reviews = true
      examples = [{ output: "x", judge_score: 4.0, human_score: 2.0, human_note: "n" }]
      allow(CompletionKit::MetricAgreementExamples).to receive(:judge_examples_for)
        .with(metric, exclude_response_id: response.id).and_return(examples)

      judge = instance_double(CompletionKit::JudgeService)
      allow(CompletionKit::JudgeService).to receive(:new).and_return(judge)
      expect(judge).to receive(:evaluate)
        .with(anything, anything, anything, hash_including(human_examples: examples))
        .and_return(score: 2.0, feedback: "ok")

      described_class.new.perform(response.id, metric.id, run.id)
    end

    it "passes no examples when the flag is off" do
      CompletionKit.config.judge_examples_from_reviews = false
      judge = instance_double(CompletionKit::JudgeService)
      allow(CompletionKit::JudgeService).to receive(:new).and_return(judge)
      expect(judge).to receive(:evaluate)
        .with(anything, anything, anything, hash_including(human_examples: nil))
        .and_return(score: 3.0, feedback: "ok")

      described_class.new.perform(response.id, metric.id, run.id)
    end

    it "passes no examples when agreement is disabled" do
      CompletionKit.config.judge_examples_from_reviews = true
      CompletionKit.config.judge_agreement_enabled = false
      judge = instance_double(CompletionKit::JudgeService)
      allow(CompletionKit::JudgeService).to receive(:new).and_return(judge)
      expect(judge).to receive(:evaluate)
        .with(anything, anything, anything, hash_including(human_examples: nil))
        .and_return(score: 3.0, feedback: "ok")

      described_class.new.perform(response.id, metric.id, run.id)
    end
  end
end

require "rails_helper"
require "faraday"

RSpec.describe CompletionKit::GenerateRowJob, type: :job do
  let(:run) { create(:completion_kit_run) }
  let(:response) { run.responses.create!(status: "pending", row_index: 0, response_text: nil) }

  before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
    allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
  end

  it "calls the LLM client and marks the response succeeded" do
    fake_client = double("client", generate_completion: "the answer", configured?: true)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    described_class.perform_now(run.id, response.id)

    response.reload
    expect(response.status).to eq("succeeded")
    expect(response.response_text).to eq("the answer")
    expect(response.error_class).to be_nil
  end

  it "marks the run as temperature_ignored when the client reports the parameter was dropped" do
    fake_client = double("client", generate_completion: "ok", configured?: true, temperature_dropped?: true)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    described_class.perform_now(run.id, response.id)

    expect(run.reload.temperature_ignored?).to be(true)
  end

  it "treats an Error: text response from the LLM client as a terminal failure" do
    fake_client = double("client", generate_completion: "Error: unexpected character: '<!DOCTYPE' at line 1 column 1", configured?: true)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    described_class.perform_now(run.id, response.id)

    response.reload
    expect(response.status).to eq("failed")
    expect(response.error_message).to include("unexpected character")
    expect(response.response_text).to be_nil
  end

  it "records a provider HTTP error as a clean failed response without paging the error tracker" do
    fake_client = double("client", generate_completion: 'Error: 402 - {"error":{"message":"Insufficient credits"}}', configured?: true)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)
    expect(Rails.error).not_to receive(:report)

    described_class.perform_now(run.id, response.id)

    response.reload
    expect(response.status).to eq("failed")
    expect(response.error_status).to eq(402)
    expect(response.error_class).to eq("CompletionKit::ProviderError")
    expect(response.error_message).to include("Insufficient credits")
  end

  it "retries a rate-limited row with backoff instead of failing it immediately" do
    fake_client = double("client", configured?: true)
    allow(fake_client).to receive(:generate_completion).and_raise(
      CompletionKit::RateLimitError.new("over budget", provider: "openai", status: 429)
    )
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    expect {
      described_class.perform_now(run.id, response.id)
    }.to have_enqueued_job(described_class)

    expect(response.reload.status).not_to eq("failed")
  end

  it "records terminal failure once rate-limit retries are exhausted" do
    fake_client = double("client", configured?: true)
    allow(fake_client).to receive(:generate_completion).and_raise(
      CompletionKit::RateLimitError.new("over budget", provider: "openai", status: 429)
    )
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    job = described_class.new(run.id, response.id)
    job.exception_executions = { "[CompletionKit::RateLimitError]" => 4 }

    expect { job.perform_now }.not_to raise_error

    response.reload
    expect(response.status).to eq("failed")
    expect(response.error_provider).to eq("openai")
    expect(response.error_status).to eq(429)
    expect(response.error_class).to eq("CompletionKit::RateLimitError")
    expect(response.error_message).to include("over budget")
  end

  it "records terminal failure once connection retries are exhausted" do
    fake_client = double("client", configured?: true)
    allow(fake_client).to receive(:generate_completion).and_raise(Faraday::TimeoutError)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    job = described_class.new(run.id, response.id)
    job.exception_executions = { "[Faraday::TimeoutError, Faraday::ConnectionFailed]" => 4 }

    expect { job.perform_now }.not_to raise_error

    response.reload
    expect(response.status).to eq("failed")
    expect(response.error_class).to eq("Faraday::TimeoutError")
  end

  it "enqueues a JudgeReviewJob per metric on success" do
    metric = create(:completion_kit_metric)
    CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)

    fake_client = double("client", generate_completion: "ok", configured?: true)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)
    allow_any_instance_of(CompletionKit::Run).to receive(:llm_judge_configured?).and_return(true)

    expect(CompletionKit::JudgeReviewJob).to receive(:perform_later).with(response.id, metric.id, run.id)

    described_class.perform_now(run.id, response.id)
  end

  it "enqueues a CheckReviewJob for each check metric regardless of judge config" do
    check = create(:completion_kit_metric, :check, check_config: { "check_kind" => "valid_json", "target" => "response_text" })
    CompletionKit::RunMetric.create!(run: run, metric: check, position: 1)

    fake_client = double("client", generate_completion: "ok", configured?: true)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    expect(CompletionKit::CheckReviewJob).to receive(:perform_later).with(response.id, check.id, run.id)
    expect(CompletionKit::JudgeReviewJob).not_to receive(:perform_later)

    described_class.perform_now(run.id, response.id)
  end

  it "enqueues RunCompletionCheckJob at the end" do
    fake_client = double("client", generate_completion: "ok", configured?: true)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    expect(CompletionKit::RunCompletionCheckJob).to receive(:perform_later).with(run.id)

    described_class.perform_now(run.id, response.id)
  end

  it "parses JSON input_data and substitutes variables" do
    run.prompt.update!(template: "Hello {{name}}")
    response.update!(input_data: '{"name":"world"}')

    fake_client = double("client", generate_completion: "Hi world", configured?: true)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    described_class.perform_now(run.id, response.id)

    response.reload
    expect(response.status).to eq("succeeded")
  end

  it "treats malformed input_data as an empty hash" do
    response.update!(input_data: "not-json{{{")

    fake_client = double("client", generate_completion: "ok", configured?: true)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    expect { described_class.perform_now(run.id, response.id) }.not_to raise_error

    response.reload
    expect(response.status).to eq("succeeded")
  end

  it "discards the job when client is not configured" do
    fake_client = double("client", configured?: false, configuration_errors: ["API key missing"])
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    expect { described_class.perform_now(run.id, response.id) }.not_to raise_error
  end

  it "skips before_perform update when response does not exist" do
    expect { described_class.perform_now(run.id, 0) }.not_to raise_error
  end

  it "records terminal failure for errors without a status method" do
    fake_client = double("client", configured?: true)
    allow(fake_client).to receive(:generate_completion).and_raise(RuntimeError, "something went wrong")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    expect {
      described_class.perform_now(run.id, response.id)
    }.not_to raise_error

    response.reload
    expect(response.status).to eq("failed")
    expect(response.error_status).to be_nil
    expect(response.error_class).to eq("RuntimeError")
  end

  it "does not raise when response_id points at a missing row (Response.find blows up, rescue swallows it)" do
    expect {
      described_class.perform_now(run.id, 0)
    }.not_to raise_error
  end

  it "rate limit wait is 30 seconds times the execution count" do
    expect(described_class.rate_limit_wait(3)).to eq(90)
    expect(described_class.rate_limit_wait(1)).to eq(30)
  end

  it "skips broadcast in before_perform when response has no run" do
    orphan = CompletionKit::Response.new(status: "pending", row_index: 0)
    orphan.run_id = run.id
    orphan.save!(validate: false)
    orphan.update_column(:run_id, nil) rescue nil

    allow(CompletionKit::Response).to receive(:find_by).and_call_original
    allow(CompletionKit::Response).to receive(:find_by).with(id: orphan.id).and_return(orphan)
    allow(orphan).to receive(:run).and_return(nil)
    allow(CompletionKit::Response).to receive(:find).and_return(orphan)
    allow(orphan).to receive(:run).and_return(nil)

    fake_client = double("client", generate_completion: "ok", configured?: true)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)
    allow(orphan).to receive(:update!).and_return(true)
    allow(orphan).to receive(:update_columns).and_return(true)

    expect { described_class.perform_now(run.id, orphan.id) }.not_to raise_error
  end

  it "returns nil from provider_for when response has no run" do
    allow(response).to receive(:run).and_return(nil)
    job = described_class.new
    expect(job.send(:provider_for, response)).to be_nil
  end

  it "concurrency key scopes to the run id" do
    key_proc = described_class.concurrency_key
    expect(key_proc.call(run.id, response.id)).to eq("run:#{run.id}")
  end
end

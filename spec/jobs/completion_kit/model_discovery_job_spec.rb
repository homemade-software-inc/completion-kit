require "rails_helper"

RSpec.describe CompletionKit::ModelDiscoveryJob, type: :job do
  let!(:credential) { create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test") }

  before do
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!)
    allow_any_instance_of(CompletionKit::ProviderCredential).to receive(:broadcast_discovery_progress)
    allow_any_instance_of(CompletionKit::ProviderCredential).to receive(:broadcast_discovery_complete)
    allow(CompletionKit::ModelDiscoveryJob).to receive(:perform_later)
  end

  it "sets discovery_status to discovering then completed" do
    described_class.perform_now(credential.id)
    credential.reload
    expect(credential.discovery_status).to eq("completed")
  end

  it "updates discovery_current via the progress callback" do
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!).and_yield(3, 10)
    described_class.perform_now(credential.id)
    credential.reload
    expect(credential.discovery_current).to eq(3)
    expect(credential.discovery_total).to eq(10)
  end

  it "sets discovery_status to failed on error" do
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!).and_raise(StandardError, "boom")
    described_class.perform_now(credential.id)
    credential.reload
    expect(credential.discovery_status).to eq("failed")
  end

  it "does not report an expected provider-side discovery error to error tracking" do
    error = CompletionKit::ModelDiscoveryService::DiscoveryError.new("No OpenAI-compatible model list was found (404)")
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!).and_raise(error)

    expect(Rails.error).not_to receive(:report)

    described_class.perform_now(credential.id)
    credential.reload
    expect(credential.discovery_status).to eq("failed")
    expect(credential.discovery_error).to include("model list")
  end

  it "reports a genuinely unexpected error as handled" do
    error = StandardError.new("boom")
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!).and_raise(error)

    expect(Rails.error).to receive(:report).with(error, hash_including(handled: true))

    described_class.perform_now(credential.id)
    expect(credential.reload.discovery_status).to eq("failed")
  end

  it "does not secondary-crash when the credential is deleted mid-discovery" do
    error = CompletionKit::ModelDiscoveryService::DiscoveryError.new("gone")
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!) do
      credential.destroy!
      raise error
    end
    allow(Rails.error).to receive(:report)

    expect { described_class.perform_now(credential.id) }.not_to raise_error
  end

  it "passes force through to the discovery service" do
    expect_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!).with(force: true)
    described_class.perform_now(credential.id, force: true)
  end

  it "persists the discovery service's catalog model count on completion" do
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:catalog_model_count).and_return(228)
    described_class.perform_now(credential.id)
    expect(credential.reload.catalog_model_count).to eq(228)
  end

  it "does nothing if credential not found" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it "retries a connection failure before it records a discovery error" do
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!).and_raise(Faraday::ConnectionFailed, "Connection refused")

    expect { described_class.perform_now(credential.id) }.to have_enqueued_job(described_class)

    credential.reload
    expect(credential.discovery_status).to eq("discovering")
    expect(credential.discovery_error).to be_nil
  end

  it "retries a rate limit before it records a discovery error" do
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!).and_raise(CompletionKit::RateLimitError, "slow down")

    expect { described_class.perform_now(credential.id) }.to have_enqueued_job(described_class)
    expect(credential.reload.discovery_error).to be_nil
  end

  it "records a rate limit once its retries are exhausted and reports it" do
    allow(Rails.error).to receive(:report)
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!).and_raise(CompletionKit::RateLimitError, "slow down")
    job = described_class.new(credential.id)
    job.exception_executions = { "[CompletionKit::RateLimitError]" => 4 }

    job.perform_now

    credential.reload
    expect(credential.discovery_status).to eq("failed")
    expect(credential.discovery_error).to eq("slow down")
    expect(Rails.error).to have_received(:report)
      .with(an_instance_of(CompletionKit::RateLimitError), handled: true, context: { job: described_class.name, provider_credential_id: credential.id })
  end

  it "does not report a connection failure while it still has retries left" do
    allow(Rails.error).to receive(:report)
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!).and_raise(Faraday::ConnectionFailed, "Connection refused")

    described_class.perform_now(credential.id)

    expect(Rails.error).not_to have_received(:report)
  end

  TransportErrors.samples.each do |label, (error, message)|
    it "records one fixed message for #{label} once retries are exhausted and reports it" do
      allow(Rails.error).to receive(:report)
      allow(Rails.logger).to receive(:warn)
      allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!).and_raise(error)
      job = described_class.new(credential.id)
      job.exception_executions = { "[Faraday::TimeoutError, Faraday::ConnectionFailed]" => 4 }

      job.perform_now

      credential.reload
      expect(credential.discovery_status).to eq("failed")
      expect(credential.discovery_error).to eq(message)
      expect(Rails.logger).to have_received(:warn).with(include(error.message))
      expect(Rails.error).to have_received(:report)
        .with(error, handled: true, context: { job: described_class.name, provider_credential_id: credential.id })
    end
  end

  it "records one fixed message when the model list is not JSON" do
    allow(Rails.error).to receive(:report)
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!).and_raise(TransportErrors.not_json)

    described_class.perform_now(credential.id)

    credential.reload
    expect(credential.discovery_status).to eq("failed")
    expect(credential.discovery_error).to eq("The endpoint did not return JSON.")
  end

  it "rate-limit wait is 30 seconds times the execution count" do
    expect(described_class.rate_limit_wait(1)).to eq(30)
    expect(described_class.rate_limit_wait(4)).to eq(120)
  end

end

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

  it "does nothing if credential not found" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end

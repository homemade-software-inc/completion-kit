require "rails_helper"
require "faraday"

RSpec.describe "End-to-end generation pipeline", type: :model do
  let(:prompt) do
    create(:completion_kit_prompt,
      name: "Summarizer", template: "Summarize {{content}} for {{audience}}",
      llm_model: "gpt-4.1")
  end

  before do
    CompletionKit::ProviderCredential.create!(provider: "openai", api_key: "test-key-123")
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
  end

  context "with a dataset" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }

    let(:dataset) do
      create(:completion_kit_dataset, csv_data: <<~CSV)
        content,audience,expected_output
        "Release notes","developers","A developer-focused summary"
        "Company update","executives","An executive briefing"
      CSV
    end

    before do
      stubs.post("/v1/chat/completions") do |env|
        body = JSON.parse(env.body)
        user_msg = body["messages"].find { |m| m["role"] == "user" }["content"]

        reply = if user_msg.include?("Release notes")
                  "Here is a developer summary of the release notes."
                else
                  "Here is an executive briefing of the company update."
                end

        [200, { "Content-Type" => "application/json" }, {
          choices: [{ message: { content: reply } }]
        }.to_json]
      end

      allow(Faraday).to receive(:new).and_wrap_original do |original, *args, **kwargs, &_block|
        original.call(*args, **kwargs) do |builder|
          builder.adapter :test, stubs
        end
      end
    end

    it "generates responses with correct input_data, response_text, and status transitions" do
      run = CompletionKit::Run.create!(prompt: prompt, dataset: dataset, name: "Pipeline test")

      expect(run.status).to eq("pending")
      run.generate_responses!

      expect(run.reload.status).to eq("completed")
      expect(run.responses.count).to eq(2)

      r1 = run.responses.order(:id).first
      expect(JSON.parse(r1.input_data)["content"]).to eq("Release notes")
      expect(r1.response_text).to include("developer summary")
      expect(r1.expected_output).to eq("A developer-focused summary")

      r2 = run.responses.order(:id).last
      expect(JSON.parse(r2.input_data)["content"]).to eq("Company update")
      expect(r2.response_text).to include("executive briefing")
    end
  end

  context "without a dataset" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }

    before do
      stubs.post("/v1/chat/completions") do
        [200, { "Content-Type" => "application/json" }, {
          choices: [{ message: { content: "Raw prompt response" } }]
        }.to_json]
      end

      allow(Faraday).to receive(:new).and_wrap_original do |original, *args, **kwargs, &_block|
        original.call(*args, **kwargs) do |builder|
          builder.adapter :test, stubs
        end
      end
    end

    it "generates a single response with nil input_data" do
      run = CompletionKit::Run.create!(prompt: prompt, dataset: nil, name: "No dataset test")

      run.generate_responses!

      expect(run.reload.status).to eq("completed")
      expect(run.responses.count).to eq(1)
      expect(run.responses.first.input_data).to be_nil
      expect(run.responses.first.response_text).to eq("Raw prompt response")
    end
  end
end

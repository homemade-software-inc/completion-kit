require "rails_helper"

RSpec.describe "Rerunning a run that could not start", type: :request do
  let(:token) { "test-api-token" }
  let(:api_headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }
  let(:api) { "/completion_kit/api/v1" }
  let(:unconfigured_message) { "LLM API not configured: OpenAI API key is not configured" }

  before do
    CompletionKit.config.api_token = token
    allow(CompletionKit::StartRunJob).to receive(:perform_later)
  end

  after { CompletionKit.instance_variable_set(:@config, nil) }

  def mcp_call(name, arguments)
    post "/completion_kit/mcp",
         params: {jsonrpc: "2.0", method: "tools/call", id: 1, params: {name: name, arguments: arguments}}.to_json,
         headers: api_headers
    JSON.parse(response.body)["result"]
  end

  def new_runs_beside(run)
    CompletionKit::Run.where.not(id: run.id)
  end

  describe "when the prompt's provider has no API key" do
    let(:run) { create(:completion_kit_run, status: "completed") }

    it "refuses through MCP, REST and the UI with the reason start! gives, without creating a copy" do
      result = mcp_call("runs_rerun", {"id" => run.id})
      expect(result["isError"]).to be(true)
      expect(result.dig("content", 0, "text")).to eq(unconfigured_message)

      post "#{api}/runs/#{run.id}/rerun", headers: api_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq(unconfigured_message)

      post "/completion_kit/runs/#{run.id}/rerun"
      expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
      expect(flash[:alert]).to eq(unconfigured_message)

      expect(new_runs_beside(run)).to be_empty
      expect(run.reload.status).to eq("completed")
    end

    it "still reruns a scoring-only run, which generates nothing" do
      dataset = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")
      scoring = create(:completion_kit_run, prompt: nil, dataset: dataset, status: "completed")

      post "/completion_kit/runs/#{scoring.id}/rerun"

      copy = new_runs_beside(scoring).sole
      expect(response).to redirect_to("/completion_kit/runs/#{copy.id}")
      expect(copy.status).to eq("running")
    end
  end

  it "reruns once the provider has a key" do
    create(:completion_kit_provider_credential)
    run = create(:completion_kit_run, status: "completed")

    post "/completion_kit/runs/#{run.id}/rerun"

    copy = new_runs_beside(run).sole
    expect(response).to redirect_to("/completion_kit/runs/#{copy.id}")
    expect(copy.status).to eq("running")
  end
end

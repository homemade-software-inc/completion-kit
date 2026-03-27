require "rails_helper"

RSpec.describe "MCP endpoint", type: :request do
  let(:mcp_path) { "/completion_kit/mcp" }
  let(:token) { "test-mcp-token" }
  let(:auth_headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  describe "authentication" do
    it "returns 401 without token" do
      post mcp_path, params: {jsonrpc: "2.0", method: "initialize", id: 1}.to_json, headers: {"Content-Type" => "application/json"}
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with wrong token" do
      post mcp_path, params: {jsonrpc: "2.0", method: "initialize", id: 1}.to_json,
        headers: {"Authorization" => "Bearer wrong", "Content-Type" => "application/json"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /mcp initialize" do
    it "returns server info and session ID" do
      post mcp_path, params: {jsonrpc: "2.0", method: "initialize", id: 1}.to_json, headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["jsonrpc"]).to eq("2.0")
      expect(body["id"]).to eq(1)
      expect(body["result"]["protocolVersion"]).to eq("2025-03-26")
      expect(body["result"]["serverInfo"]["name"]).to eq("CompletionKit")
      expect(body["result"]["capabilities"]["tools"]).to be_present
      expect(response.headers["Mcp-Session-Id"]).to be_present
    end
  end

  describe "session validation" do
    it "returns error for tools/list without session" do
      post mcp_path, params: {jsonrpc: "2.0", method: "tools/list", id: 2}.to_json, headers: auth_headers
      expect(response).to have_http_status(:bad_request)
    end

    it "allows tools/list with valid session" do
      post mcp_path, params: {jsonrpc: "2.0", method: "initialize", id: 1}.to_json, headers: auth_headers
      session_id = response.headers["Mcp-Session-Id"]

      post mcp_path, params: {jsonrpc: "2.0", method: "tools/list", id: 2}.to_json,
        headers: auth_headers.merge("Mcp-Session-Id" => session_id)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["result"]["tools"]).to be_an(Array)
    end
  end

  describe "DELETE /mcp" do
    it "clears the session" do
      post mcp_path, params: {jsonrpc: "2.0", method: "initialize", id: 1}.to_json, headers: auth_headers
      session_id = response.headers["Mcp-Session-Id"]

      delete mcp_path, headers: auth_headers.merge("Mcp-Session-Id" => session_id)
      expect(response).to have_http_status(:ok)

      post mcp_path, params: {jsonrpc: "2.0", method: "tools/list", id: 2}.to_json,
        headers: auth_headers.merge("Mcp-Session-Id" => session_id)
      expect(response).to have_http_status(:bad_request)
    end
  end
end

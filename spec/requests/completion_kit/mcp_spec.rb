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
    it "handles delete without session header" do
      delete mcp_path, headers: auth_headers
      expect(response).to have_http_status(:ok)
    end

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

  describe "tools/call through HTTP" do
    let(:session_id) do
      post mcp_path, params: {jsonrpc: "2.0", method: "initialize", id: 1}.to_json, headers: auth_headers
      response.headers["Mcp-Session-Id"]
    end
    let(:session_headers) { auth_headers.merge("Mcp-Session-Id" => session_id) }

    it "creates and lists prompts" do
      post mcp_path, params: {jsonrpc: "2.0", id: 2, method: "tools/call", params: {
        name: "prompts_create", arguments: {name: "MCP Prompt", template: "Hi {{name}}", llm_model: "gpt-4.1"}
      }}.to_json, headers: session_headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      created = JSON.parse(body["result"]["content"].first["text"])
      expect(created["name"]).to eq("MCP Prompt")

      post mcp_path, params: {jsonrpc: "2.0", id: 3, method: "tools/call", params: {
        name: "prompts_list", arguments: {}
      }}.to_json, headers: session_headers
      body = JSON.parse(response.body)
      list = JSON.parse(body["result"]["content"].first["text"])
      expect(list.length).to eq(1)
    end

    it "returns JSON-RPC error for unknown tool" do
      post mcp_path, params: {jsonrpc: "2.0", id: 4, method: "tools/call", params: {
        name: "nonexistent_tool", arguments: {}
      }}.to_json, headers: session_headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32601)
    end

    it "returns JSON-RPC error for unknown method" do
      post mcp_path, params: {jsonrpc: "2.0", id: 5, method: "resources/list", params: {}}.to_json, headers: session_headers
      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32601)
    end

    it "handles malformed JSON" do
      post mcp_path, params: "not json", headers: session_headers
      expect(response).to have_http_status(:bad_request)
      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32700)
    end

    it "returns JSON-RPC error for invalid params" do
      allow(CompletionKit::McpDispatcher).to receive(:dispatch)
        .and_raise(CompletionKit::McpDispatcher::InvalidParams, "Missing required param")
      post mcp_path, params: {jsonrpc: "2.0", id: 6, method: "tools/call", params: {
        name: "prompts_create", arguments: {}
      }}.to_json, headers: session_headers
      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32602)
    end

    it "handles notifications/initialized as no-op" do
      post mcp_path, params: {jsonrpc: "2.0", method: "notifications/initialized"}.to_json, headers: session_headers
      expect(response).to have_http_status(:ok)
    end

    it "handles MethodNotFound with nil request_body id" do
      post mcp_path, params: {jsonrpc: "2.0", method: "bogus/method"}.to_json, headers: session_headers
      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32601)
      expect(body["id"]).to be_nil
    end

    it "returns JSON-RPC error for RecordNotFound" do
      post mcp_path, params: {jsonrpc: "2.0", id: 10, method: "tools/call", params: {
        name: "prompts_get", arguments: {id: 999999}
      }}.to_json, headers: session_headers
      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32602)
    end

    it "returns JSON-RPC error for RecordInvalid" do
      post mcp_path, params: {jsonrpc: "2.0", id: 11, method: "tools/call", params: {
        name: "prompts_create", arguments: {name: "", template: "", llm_model: ""}
      }}.to_json, headers: session_headers
      expect(response).to have_http_status(:ok)
    end

    it "returns JSON-RPC InvalidParams when a tool raises ActiveRecord::RecordInvalid" do
      invalid_record = CompletionKit::Prompt.new
      invalid_record.errors.add(:name, "can't be blank")
      allow(CompletionKit::McpDispatcher).to receive(:dispatch)
        .and_raise(ActiveRecord::RecordInvalid.new(invalid_record))

      post mcp_path, params: {jsonrpc: "2.0", id: 13, method: "tools/call", params: {
        name: "prompts_create", arguments: {}
      }}.to_json, headers: session_headers

      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32602)
      expect(body["error"]["message"]).to include("Name can't be blank")
    end

    it "returns JSON-RPC InvalidParams when a tool raises ActiveRecord::InvalidForeignKey" do
      allow(CompletionKit::McpDispatcher).to receive(:dispatch)
        .and_raise(ActiveRecord::InvalidForeignKey, "foreign key constraint violated")

      post mcp_path, params: {jsonrpc: "2.0", id: 14, method: "tools/call", params: {
        name: "prompts_delete", arguments: {id: 1}
      }}.to_json, headers: session_headers

      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32602)
      expect(body["error"]["message"]).to include("foreign key")
    end

    it "returns JSON-RPC error for unexpected StandardError" do
      allow(CompletionKit::McpDispatcher).to receive(:dispatch)
        .and_raise(StandardError, "something broke")
      post mcp_path, params: {jsonrpc: "2.0", id: 12, method: "tools/call", params: {
        name: "prompts_list", arguments: {}
      }}.to_json, headers: session_headers
      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32603)
      expect(body["error"]["message"]).to eq("something broke")
    end
  end
end

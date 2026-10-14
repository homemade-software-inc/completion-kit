require "rails_helper"

RSpec.describe "MCP endpoint", type: :request do
  let(:mcp_path) { "/completion_kit/mcp" }
  let(:token) { "test-mcp-token" }
  let(:auth_headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  def sql_writes_during
    writes = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      writes << payload[:sql] if payload[:sql].match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i)
    end
    yield
    writes
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe "authentication" do
    let(:no_auth) { {"Content-Type" => "application/json"} }

    it "allows initialize without a token (public discovery method)" do
      post mcp_path, params: {jsonrpc: "2.0", method: "initialize", id: 1}.to_json, headers: no_auth
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["result"]["serverInfo"]["name"]).to eq("CompletionKit")
    end

    it "writes nothing to the database for an unauthenticated initialize" do
      writes = sql_writes_during do
        post mcp_path, params: {jsonrpc: "2.0", method: "initialize", id: 1}.to_json, headers: no_auth
      end

      expect(response).to have_http_status(:ok)
      expect(response.headers["Mcp-Session-Id"]).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      expect(writes).to be_empty
    end

    it "allows tools/list without a token (public discovery method)" do
      post mcp_path, params: {jsonrpc: "2.0", method: "tools/list", id: 2}.to_json, headers: no_auth
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["result"]["tools"]).to be_an(Array)
    end

    it "returns 401 for a data method (tools/call) without token" do
      post mcp_path, params: {jsonrpc: "2.0", method: "tools/call", id: 3, params: {name: "prompts_list", arguments: {}}}.to_json, headers: no_auth
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for a data method (tools/call) with wrong token" do
      post mcp_path, params: {jsonrpc: "2.0", method: "tools/call", id: 3, params: {name: "prompts_list", arguments: {}}}.to_json,
        headers: {"Authorization" => "Bearer wrong", "Content-Type" => "application/json"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /mcp (health-check probe)" do
    it "returns 405 with an Allow header rather than 404, without requiring a token" do
      get mcp_path
      expect(response).to have_http_status(:method_not_allowed)
      expect(response.headers["Allow"]).to eq("POST, DELETE")
      expect(response.body).to be_blank
    end
  end

  describe "POST /mcp initialize" do
    it "returns server info and session ID" do
      post mcp_path, params: {jsonrpc: "2.0", method: "initialize", id: 1}.to_json, headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["jsonrpc"]).to eq("2.0")
      expect(body["id"]).to eq(1)
      expect(body["result"]["protocolVersion"]).to eq("2025-06-18")
      expect(body["result"]["serverInfo"]["name"]).to eq("CompletionKit")
      expect(body["result"]["capabilities"]["tools"]).to be_present
      expect(response.headers["Mcp-Session-Id"]).to be_present
    end
  end

  describe "stateless operation" do
    it "serves tools/list without a session id" do
      post mcp_path, params: {jsonrpc: "2.0", method: "tools/list", id: 2}.to_json, headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["result"]["tools"]).to be_an(Array)
    end

    it "serves tools/list even with an unknown or expired session id" do
      post mcp_path, params: {jsonrpc: "2.0", method: "tools/list", id: 2}.to_json,
        headers: auth_headers.merge("Mcp-Session-Id" => "expired-or-unknown")
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["result"]["tools"]).to be_an(Array)
    end

    it "serves an authenticated tools/call without a session id" do
      post mcp_path, params: {jsonrpc: "2.0", id: 3, method: "tools/call", params: {name: "prompts_list", arguments: {}}}.to_json,
        headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["result"]["content"]).to be_an(Array)
    end

    it "serves an authenticated tools/call with an unknown session id" do
      post mcp_path, params: {jsonrpc: "2.0", id: 3, method: "tools/call", params: {name: "prompts_list", arguments: {}}}.to_json,
        headers: auth_headers.merge("Mcp-Session-Id" => "expired-or-unknown")
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["result"]["content"]).to be_an(Array)
    end

    it "still accepts a session id minted by initialize" do
      post mcp_path, params: {jsonrpc: "2.0", method: "initialize", id: 1}.to_json, headers: auth_headers
      session_id = response.headers["Mcp-Session-Id"]

      post mcp_path, params: {jsonrpc: "2.0", method: "tools/list", id: 2}.to_json,
        headers: auth_headers.merge("Mcp-Session-Id" => session_id)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["result"]["tools"]).to be_an(Array)
    end
  end

  describe "DELETE /mcp" do
    it "handles delete without session header" do
      delete mcp_path, headers: auth_headers
      expect(response).to have_http_status(:ok)
    end

    it "answers 200 for a session id without touching the database" do
      writes = sql_writes_during do
        delete mcp_path, headers: auth_headers.merge("Mcp-Session-Id" => SecureRandom.uuid)
      end

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_blank
      expect(writes).to be_empty
    end

    it "still requires a token" do
      delete mcp_path
      expect(response).to have_http_status(:unauthorized)
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

    it "starts a run over a dataset at the upload limit without reading the whole file in the request" do
      create(:completion_kit_provider_credential)
      header = "content,audience,expected_output\n"
      body = header + ("a,b,c\n" * ((CompletionKit.config.max_upload_bytes - header.bytesize) / 6))
      dataset = create(:completion_kit_dataset, csv_data: body)
      prompt = create(:completion_kit_prompt, template: "Write {{content}} for {{audience}}")
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset, expected_column: "expected_output")
      sizes = track_csv_reads
      expect_any_instance_of(CompletionKit::Dataset).not_to receive(:row_count)

      expect {
        post mcp_path, params: {jsonrpc: "2.0", id: 6, method: "tools/call", params: {
          name: "runs_generate", arguments: {id: run.id}
        }}.to_json, headers: session_headers
      }.to have_enqueued_job(CompletionKit::StartRunJob)

      result = JSON.parse(JSON.parse(response.body)["result"]["content"].first["text"])
      expect(result["status"]).to eq("running")
      expect(sizes).not_to be_empty
      expect(sizes.max).to eq(header.chomp.bytesize)
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

    it "rejects a JSON-RPC batch with Invalid Request instead of a 500" do
      batch = [
        {jsonrpc: "2.0", id: 1, method: "tools/list"},
        {jsonrpc: "2.0", id: 2, method: "tools/call", params: {name: "prompts_list", arguments: {}}}
      ]
      post mcp_path, params: batch.to_json, headers: session_headers
      expect(response).to have_http_status(:bad_request)
      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32600)
      expect(body["id"]).to be_nil
    end

    it "rejects an unauthenticated batch that pairs a public method with a protected call" do
      batch = [
        {jsonrpc: "2.0", id: 1, method: "initialize"},
        {jsonrpc: "2.0", id: 2, method: "tools/call", params: {name: "prompts_list", arguments: {}}}
      ]
      expect(CompletionKit::McpDispatcher).not_to receive(:dispatch)
      post mcp_path, params: batch.to_json, headers: {"Content-Type" => "application/json"}
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]["code"]).to eq(-32600)
    end

    ["42", "\"x\"", "null", "[]"].each do |raw|
      it "rejects the non-object body #{raw} with Invalid Request" do
        post mcp_path, params: raw, headers: session_headers
        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)["error"]["code"]).to eq(-32600)
      end
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
      expect(body["error"]["message"]).to eq("Prompt 999999 not found")
    end

    it "names the model and id when datasets_get misses" do
      post mcp_path, params: {jsonrpc: "2.0", id: 15, method: "tools/call", params: {
        name: "datasets_get", arguments: {id: 424242}
      }}.to_json, headers: session_headers
      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32602)
      expect(body["error"]["message"]).to eq("Dataset 424242 not found")
    end

    it "keeps the relation's conditions out of a responses_get miss" do
      response_row = create(:completion_kit_response)
      other_run = create(:completion_kit_run)

      post mcp_path, params: {jsonrpc: "2.0", id: 16, method: "tools/call", params: {
        name: "responses_get", arguments: {run_id: other_run.id, id: response_row.id}
      }}.to_json, headers: session_headers
      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32602)
      expect(body["error"]["message"]).to eq("Response #{response_row.id} not found")
      expect(body["error"]["message"]).not_to include("WHERE")
      expect(body["error"]["message"]).not_to include("run_id")
    end

    it "falls back to a fixed message when RecordNotFound carries no model or id" do
      allow(CompletionKit::McpDispatcher).to receive(:dispatch).and_raise(ActiveRecord::RecordNotFound)
      post mcp_path, params: {jsonrpc: "2.0", id: 17, method: "tools/call", params: {
        name: "prompts_get", arguments: {id: "missing"}
      }}.to_json, headers: session_headers
      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32602)
      expect(body["error"]["message"]).to eq("Record not found")
    end

    describe "with a host tenant scope" do
      let(:tenant_not_found) do
        lambda do |id|
          with_tenant(2) { CompletionKit::TenantedThing.find(id) }
        rescue ActiveRecord::RecordNotFound => e
          e
        end
      end

      def call_with(error)
        allow(CompletionKit::McpDispatcher).to receive(:dispatch).and_raise(error)
        post mcp_path, params: {jsonrpc: "2.0", id: 18, method: "tools/call", params: {
          name: "datasets_get", arguments: {id: 1}
        }}.to_json, headers: session_headers
        response.body
      end

      before { session_id }

      it "hides the scope SQL and answers an out-of-scope id the same as a missing one" do
        configure_tenant_scope
        thing = with_tenant(1) { CompletionKit::TenantedThing.create!(label: "theirs", organization_id: 1) }

        out_of_scope = tenant_not_found.call(thing.id)
        expect(out_of_scope.message).to include("WHERE")
        out_of_scope_body = call_with(out_of_scope)

        error = JSON.parse(out_of_scope_body)["error"]
        expect(error["code"]).to eq(-32602)
        expect(error["message"]).to eq("Tenanted Thing #{thing.id} not found")
        expect(error["message"]).not_to include("WHERE")
        expect(error["message"]).not_to include("organization_id")
        expect(error["message"]).not_to include("completion_kit_tenanted_things")

        with_tenant(1) { thing.destroy! }
        missing_body = call_with(tenant_not_found.call(thing.id))
        expect(missing_body).to eq(out_of_scope_body)
      end
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

    it "returns a fixed JSON-RPC InvalidParams message when a tool raises ActiveRecord::InvalidForeignKey" do
      error = ActiveRecord::InvalidForeignKey.new(
        "PG::ForeignKeyViolation: ERROR:  update or delete on table \"completion_kit_prompts\" violates foreign key " \
        "constraint \"fk_rails_123\" on table \"completion_kit_runs\"\nDETAIL:  Key (id)=(1) is still referenced from table \"completion_kit_runs\"."
      )
      allow(CompletionKit::McpDispatcher).to receive(:dispatch).and_raise(error)
      expect(Rails.error).to receive(:report).with(error, hash_including(handled: true))

      post mcp_path, params: {jsonrpc: "2.0", id: 14, method: "tools/call", params: {
        name: "prompts_delete", arguments: {id: 1}
      }}.to_json, headers: session_headers

      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32602)
      expect(body["error"]["message"]).to eq("This change references a record that does not exist or is still in use.")
      expect(body["error"]["message"]).not_to include("PG::")
      expect(body["error"]["message"]).not_to include("DETAIL")
      expect(body["error"]["message"]).not_to include("constraint")
    end

    it "says the input was too large or too complex when a tool hits a regex timeout" do
      error = Regexp::TimeoutError.new("regexp match timeout")
      allow(CompletionKit::McpDispatcher).to receive(:dispatch).and_raise(error)
      expect(Rails.error).to receive(:report).with(error, hash_including(handled: true))

      post mcp_path, params: {jsonrpc: "2.0", id: 15, method: "tools/call", params: {
        name: "runs_create", arguments: {}
      }}.to_json, headers: session_headers

      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body["id"]).to eq(15)
      expect(body["error"]["code"]).to eq(-32602)
      expect(body["error"]["message"]).to eq("The input was too large or too complex to process.")
    end

    it "returns a generic JSON-RPC error for an unexpected StandardError" do
      allow(CompletionKit::McpDispatcher).to receive(:dispatch)
        .and_raise(StandardError, "something broke")
      post mcp_path, params: {jsonrpc: "2.0", id: 12, method: "tools/call", params: {
        name: "prompts_list", arguments: {}
      }}.to_json, headers: session_headers
      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq(-32603)
      expect(body["error"]["message"]).to eq("Internal error")
    end
  end
end

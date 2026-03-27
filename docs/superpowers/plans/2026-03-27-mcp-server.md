# MCP Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hosted MCP server to the CompletionKit engine so any Rails app mounting the engine gets an MCP endpoint at `/mcp`.

**Architecture:** Three-layer design — `McpController` handles HTTP transport and auth (inherits from `Api::V1::BaseController`), `McpDispatcher` routes JSON-RPC methods, and `McpTools::*` modules contain per-resource business logic calling existing models/services. Streamable HTTP transport with SSE for long-running operations.

**Tech Stack:** Rails 8.1, JSON-RPC 2.0, Server-Sent Events, RSpec

---

## File Structure

```
app/controllers/completion_kit/mcp_controller.rb        — HTTP transport, auth, SSE
app/services/completion_kit/mcp_dispatcher.rb            — JSON-RPC routing
app/services/completion_kit/mcp_tools/prompts.rb         — prompt tools
app/services/completion_kit/mcp_tools/runs.rb            — run tools (SSE generate/judge)
app/services/completion_kit/mcp_tools/responses.rb       — response tools
app/services/completion_kit/mcp_tools/datasets.rb        — dataset tools
app/services/completion_kit/mcp_tools/metrics.rb         — metric tools
app/services/completion_kit/mcp_tools/criteria.rb        — criteria tools
app/services/completion_kit/mcp_tools/provider_credentials.rb — provider credential tools
config/routes.rb                                         — add MCP routes
spec/services/completion_kit/mcp_dispatcher_spec.rb      — dispatcher unit tests
spec/services/completion_kit/mcp_tools/*_spec.rb         — tool unit tests
spec/requests/completion_kit/mcp_spec.rb                 — integration tests
```

---

### Task 1: MCP route and controller skeleton

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/completion_kit/mcp_controller.rb`
- Create: `spec/requests/completion_kit/mcp_spec.rb`

- [ ] **Step 1: Write the failing test for auth and basic POST /mcp**

```ruby
# spec/requests/completion_kit/mcp_spec.rb
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/completion_kit/mcp_spec.rb`
Expected: routing error — no route matches POST /completion_kit/mcp

- [ ] **Step 3: Add routes**

```ruby
# config/routes.rb — add inside the Engine.routes.draw block, after the api namespace
post "mcp", to: "mcp#handle"
delete "mcp", to: "mcp#destroy"
```

- [ ] **Step 4: Write the controller**

```ruby
# app/controllers/completion_kit/mcp_controller.rb
module CompletionKit
  class McpController < Api::V1::BaseController
    def handle
      request_body = JSON.parse(request.body.read)

      if request_body["method"] == "initialize"
        result = McpDispatcher.initialize_session
        session_id = result.delete(:session_id)
        response.headers["Mcp-Session-Id"] = session_id
        render json: jsonrpc_response(request_body["id"], result)
        return
      end

      if request_body["method"] == "notifications/initialized"
        head :ok
        return
      end

      session_id = request.headers["Mcp-Session-Id"]
      unless session_id && Rails.cache.exist?("mcp_session:#{session_id}")
        render json: jsonrpc_error(request_body["id"], -32000, "Session not initialized. Send initialize first."), status: :bad_request
        return
      end

      result = McpDispatcher.dispatch(request_body["method"], request_body["params"])
      render json: jsonrpc_response(request_body["id"], result)
    rescue JSON::ParserError
      render json: jsonrpc_error(nil, -32700, "Parse error"), status: :bad_request
    rescue McpDispatcher::MethodNotFound => e
      render json: jsonrpc_error(request_body&.dig("id"), -32601, e.message), status: :ok
    rescue McpDispatcher::InvalidParams => e
      render json: jsonrpc_error(request_body&.dig("id"), -32602, e.message), status: :ok
    end

    def destroy
      session_id = request.headers["Mcp-Session-Id"]
      Rails.cache.delete("mcp_session:#{session_id}") if session_id
      head :ok
    end

    private

    def jsonrpc_response(id, result)
      {jsonrpc: "2.0", id: id, result: result}
    end

    def jsonrpc_error(id, code, message)
      {jsonrpc: "2.0", id: id, error: {code: code, message: message}}
    end
  end
end
```

- [ ] **Step 5: Write the dispatcher skeleton (initialize + tools/list only)**

```ruby
# app/services/completion_kit/mcp_dispatcher.rb
module CompletionKit
  class McpDispatcher
    class MethodNotFound < StandardError; end
    class InvalidParams < StandardError; end

    PROTOCOL_VERSION = "2025-03-26"

    def self.initialize_session
      session_id = SecureRandom.uuid
      Rails.cache.write("mcp_session:#{session_id}", true, expires_in: 1.hour)
      {
        session_id: session_id,
        protocolVersion: PROTOCOL_VERSION,
        serverInfo: {name: "CompletionKit", version: CompletionKit::VERSION},
        capabilities: {tools: {listChanged: false}}
      }
    end

    def self.dispatch(method, params)
      case method
      when "tools/list"
        {tools: tool_definitions}
      when "tools/call"
        call_tool(params&.dig("name"), params&.dig("arguments") || {})
      else
        raise MethodNotFound, "Method not found: #{method}"
      end
    end

    def self.tool_definitions
      []
    end

    def self.call_tool(name, arguments)
      raise MethodNotFound, "Unknown tool: #{name}"
    end
  end
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/requests/completion_kit/mcp_spec.rb`
Expected: all pass

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/completion_kit/mcp_controller.rb app/services/completion_kit/mcp_dispatcher.rb spec/requests/completion_kit/mcp_spec.rb
git commit -m "feat: add MCP controller, dispatcher skeleton, and routes"
```

---

### Task 2: Prompt tools

**Files:**
- Create: `app/services/completion_kit/mcp_tools/prompts.rb`
- Create: `spec/services/completion_kit/mcp_tools/prompts_spec.rb`
- Modify: `app/services/completion_kit/mcp_dispatcher.rb`

- [ ] **Step 1: Write the failing tool unit tests**

```ruby
# spec/services/completion_kit/mcp_tools/prompts_spec.rb
require "rails_helper"

RSpec.describe CompletionKit::McpTools::Prompts do
  describe ".definitions" do
    it "returns 7 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(7)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        prompts_list prompts_get prompts_create prompts_update
        prompts_delete prompts_publish prompts_new_version
      ])
    end

    it "includes inputSchema for each tool" do
      described_class.definitions.each do |tool|
        expect(tool[:inputSchema]).to be_a(Hash)
        expect(tool[:inputSchema][:type]).to eq("object")
      end
    end
  end

  describe ".call" do
    let!(:prompt) { create(:completion_kit_prompt, name: "Test Prompt") }

    it "lists prompts" do
      result = described_class.call("prompts_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content).to be_an(Array)
      expect(content.first["name"]).to eq("Test Prompt")
    end

    it "gets a prompt by id" do
      result = described_class.call("prompts_get", {"id" => prompt.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(prompt.id)
    end

    it "creates a prompt" do
      result = described_class.call("prompts_create", {
        "name" => "New Prompt", "template" => "Hello {{name}}", "llm_model" => "gpt-4.1"
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("New Prompt")
      expect(CompletionKit::Prompt.count).to eq(2)
    end

    it "updates a prompt" do
      result = described_class.call("prompts_update", {"id" => prompt.id, "name" => "Updated"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Updated")
    end

    it "deletes a prompt" do
      result = described_class.call("prompts_delete", {"id" => prompt.id})
      expect(result[:content].first[:text]).to include("deleted")
      expect(CompletionKit::Prompt.count).to eq(0)
    end

    it "publishes a prompt" do
      result = described_class.call("prompts_publish", {"id" => prompt.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["current"]).to be true
    end

    it "creates a new version" do
      result = described_class.call("prompts_new_version", {"id" => prompt.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["version_number"]).to eq(2)
      expect(CompletionKit::Prompt.count).to eq(2)
    end

    it "returns error for unknown tool" do
      expect { described_class.call("prompts_bogus", {}) }.to raise_error(KeyError)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/prompts_spec.rb`
Expected: FAIL — uninitialized constant CompletionKit::McpTools::Prompts

- [ ] **Step 3: Implement the prompts tools module**

```ruby
# app/services/completion_kit/mcp_tools/prompts.rb
module CompletionKit
  module McpTools
    module Prompts
      TOOLS = {
        "prompts_list" => {
          description: "List all prompts",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "prompts_get" => {
          description: "Get a prompt by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer", description: "Prompt ID"}}, required: ["id"]},
          handler: :get
        },
        "prompts_create" => {
          description: "Create a prompt",
          inputSchema: {
            type: "object",
            properties: {
              name: {type: "string"}, description: {type: "string"},
              template: {type: "string"}, llm_model: {type: "string"}
            },
            required: ["name", "template", "llm_model"]
          },
          handler: :create
        },
        "prompts_update" => {
          description: "Update a prompt",
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, name: {type: "string"}, description: {type: "string"},
              template: {type: "string"}, llm_model: {type: "string"}
            },
            required: ["id"]
          },
          handler: :update
        },
        "prompts_delete" => {
          description: "Delete a prompt",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        },
        "prompts_publish" => {
          description: "Publish a prompt version, making it the current version",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :publish
        },
        "prompts_new_version" => {
          description: "Create a new draft version of a prompt",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :new_version
        }
      }.freeze

      def self.definitions
        TOOLS.map { |name, config| {name: name, description: config[:description], inputSchema: config[:inputSchema]} }
      end

      def self.call(name, arguments)
        tool = TOOLS.fetch(name)
        send(tool[:handler], arguments)
      end

      def self.list(_args)
        text_result(Prompt.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(Prompt.find(args["id"]).as_json)
      end

      def self.create(args)
        prompt = Prompt.new(args.slice("name", "description", "template", "llm_model"))
        if prompt.save
          text_result(prompt.as_json)
        else
          error_result(prompt.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        prompt = Prompt.find(args["id"])
        if prompt.update(args.except("id").slice("name", "description", "template", "llm_model"))
          text_result(prompt.as_json)
        else
          error_result(prompt.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        Prompt.find(args["id"]).destroy!
        text_result("Prompt #{args["id"]} deleted")
      end

      def self.publish(args)
        prompt = Prompt.find(args["id"])
        prompt.publish!
        text_result(prompt.reload.as_json)
      end

      def self.new_version(args)
        prompt = Prompt.find(args["id"])
        version = prompt.clone_as_new_version
        text_result(version.as_json)
      end

      def self.text_result(data)
        text = data.is_a?(String) ? data : data.to_json
        {content: [{type: "text", text: text}]}
      end

      def self.error_result(message)
        {content: [{type: "text", text: message}], isError: true}
      end
    end
  end
end
```

- [ ] **Step 4: Register prompts tools in the dispatcher**

Update `app/services/completion_kit/mcp_dispatcher.rb`:

```ruby
def self.tool_definitions
  McpTools::Prompts.definitions
end

def self.call_tool(name, arguments)
  case name
  when /\Aprompts_/
    McpTools::Prompts.call(name, arguments)
  else
    raise MethodNotFound, "Unknown tool: #{name}"
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/prompts_spec.rb`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add app/services/completion_kit/mcp_tools/prompts.rb app/services/completion_kit/mcp_dispatcher.rb spec/services/completion_kit/mcp_tools/prompts_spec.rb
git commit -m "feat: add MCP prompt tools"
```

---

### Task 3: Run tools

**Files:**
- Create: `app/services/completion_kit/mcp_tools/runs.rb`
- Create: `spec/services/completion_kit/mcp_tools/runs_spec.rb`
- Modify: `app/services/completion_kit/mcp_dispatcher.rb`

- [ ] **Step 1: Write the failing tool unit tests**

```ruby
# spec/services/completion_kit/mcp_tools/runs_spec.rb
require "rails_helper"

RSpec.describe CompletionKit::McpTools::Runs do
  describe ".definitions" do
    it "returns 7 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(7)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        runs_list runs_get runs_create runs_update
        runs_delete runs_generate runs_judge
      ])
    end
  end

  describe ".call" do
    let!(:prompt) { create(:completion_kit_prompt) }
    let!(:run) { create(:completion_kit_run, prompt: prompt, name: "Test Run") }

    it "lists runs" do
      result = described_class.call("runs_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content).to be_an(Array)
      expect(content.first["name"]).to eq("Test Run")
    end

    it "gets a run by id" do
      result = described_class.call("runs_get", {"id" => run.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(run.id)
    end

    it "creates a run" do
      result = described_class.call("runs_create", {"name" => "New Run", "prompt_id" => prompt.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("New Run")
    end

    it "creates a run with metric_ids" do
      metric = create(:completion_kit_metric)
      result = described_class.call("runs_create", {"name" => "Run M", "prompt_id" => prompt.id, "metric_ids" => [metric.id]})
      content = JSON.parse(result[:content].first[:text])
      expect(content["metric_ids"]).to eq([metric.id])
    end

    it "updates a run" do
      result = described_class.call("runs_update", {"id" => run.id, "name" => "Updated"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Updated")
    end

    it "deletes a run" do
      result = described_class.call("runs_delete", {"id" => run.id})
      expect(result[:content].first[:text]).to include("deleted")
    end

    it "enqueues generate" do
      result = described_class.call("runs_generate", {"id" => run.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(run.id)
    end

    it "enqueues judge" do
      result = described_class.call("runs_judge", {"id" => run.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(run.id)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/runs_spec.rb`
Expected: FAIL — uninitialized constant CompletionKit::McpTools::Runs

- [ ] **Step 3: Implement the runs tools module**

```ruby
# app/services/completion_kit/mcp_tools/runs.rb
module CompletionKit
  module McpTools
    module Runs
      TOOLS = {
        "runs_list" => {
          description: "List all runs",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "runs_get" => {
          description: "Get a run by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "runs_create" => {
          description: "Create a run",
          inputSchema: {
            type: "object",
            properties: {
              name: {type: "string"}, prompt_id: {type: "integer"},
              dataset_id: {type: "integer"}, judge_model: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}}
            },
            required: ["name", "prompt_id"]
          },
          handler: :create
        },
        "runs_update" => {
          description: "Update a run",
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, name: {type: "string"},
              dataset_id: {type: "integer"}, judge_model: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}}
            },
            required: ["id"]
          },
          handler: :update
        },
        "runs_delete" => {
          description: "Delete a run",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        },
        "runs_generate" => {
          description: "Generate responses for a run using its prompt and dataset",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :generate
        },
        "runs_judge" => {
          description: "Judge responses for a run using configured metrics",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :judge
        }
      }.freeze

      def self.definitions
        TOOLS.map { |name, config| {name: name, description: config[:description], inputSchema: config[:inputSchema]} }
      end

      def self.call(name, arguments)
        tool = TOOLS.fetch(name)
        send(tool[:handler], arguments)
      end

      def self.list(_args)
        text_result(Run.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(Run.find(args["id"]).as_json)
      end

      def self.create(args)
        run = Run.new(args.slice("name", "prompt_id", "dataset_id", "judge_model"))
        if run.save
          replace_run_metrics(run, args["metric_ids"])
          text_result(run.reload.as_json)
        else
          error_result(run.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        run = Run.find(args["id"])
        if run.update(args.except("id", "metric_ids").slice("name", "dataset_id", "judge_model"))
          replace_run_metrics(run, args["metric_ids"]) if args.key?("metric_ids")
          text_result(run.reload.as_json)
        else
          error_result(run.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        Run.find(args["id"]).destroy!
        text_result("Run #{args["id"]} deleted")
      end

      def self.generate(args)
        run = Run.find(args["id"])
        GenerateJob.perform_later(run.id)
        text_result(run.reload.as_json)
      end

      def self.judge(args)
        run = Run.find(args["id"])
        JudgeJob.perform_later(run.id)
        text_result(run.reload.as_json)
      end

      def self.text_result(data)
        text = data.is_a?(String) ? data : data.to_json
        {content: [{type: "text", text: text}]}
      end

      def self.error_result(message)
        {content: [{type: "text", text: message}], isError: true}
      end

      def self.replace_run_metrics(run, metric_ids)
        return unless metric_ids
        run.run_metrics.delete_all
        Array(metric_ids).reject(&:blank?).each_with_index do |metric_id, index|
          run.run_metrics.create!(metric_id: metric_id, position: index + 1)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Register runs tools in the dispatcher**

Update `app/services/completion_kit/mcp_dispatcher.rb` — add to `tool_definitions` and `call_tool`:

```ruby
def self.tool_definitions
  McpTools::Prompts.definitions + McpTools::Runs.definitions
end

def self.call_tool(name, arguments)
  case name
  when /\Aprompts_/
    McpTools::Prompts.call(name, arguments)
  when /\Aruns_/
    McpTools::Runs.call(name, arguments)
  else
    raise MethodNotFound, "Unknown tool: #{name}"
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/runs_spec.rb`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add app/services/completion_kit/mcp_tools/runs.rb app/services/completion_kit/mcp_dispatcher.rb spec/services/completion_kit/mcp_tools/runs_spec.rb
git commit -m "feat: add MCP run tools"
```

---

### Task 4: Response tools

**Files:**
- Create: `app/services/completion_kit/mcp_tools/responses.rb`
- Create: `spec/services/completion_kit/mcp_tools/responses_spec.rb`
- Modify: `app/services/completion_kit/mcp_dispatcher.rb`

- [ ] **Step 1: Write the failing tool unit tests**

```ruby
# spec/services/completion_kit/mcp_tools/responses_spec.rb
require "rails_helper"

RSpec.describe CompletionKit::McpTools::Responses do
  describe ".definitions" do
    it "returns 2 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(2)
      expect(defs.map { |d| d[:name] }).to match_array(%w[responses_list responses_get])
    end
  end

  describe ".call" do
    let!(:prompt) { create(:completion_kit_prompt) }
    let!(:run) { create(:completion_kit_run, prompt: prompt) }
    let!(:response_record) { create(:completion_kit_response, run: run, response_text: "Hello") }

    it "lists responses for a run" do
      result = described_class.call("responses_list", {"run_id" => run.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content).to be_an(Array)
      expect(content.first["response_text"]).to eq("Hello")
    end

    it "gets a response by id" do
      result = described_class.call("responses_get", {"run_id" => run.id, "id" => response_record.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(response_record.id)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/responses_spec.rb`
Expected: FAIL — uninitialized constant

- [ ] **Step 3: Implement the responses tools module**

```ruby
# app/services/completion_kit/mcp_tools/responses.rb
module CompletionKit
  module McpTools
    module Responses
      TOOLS = {
        "responses_list" => {
          description: "List responses for a run",
          inputSchema: {type: "object", properties: {run_id: {type: "integer"}}, required: ["run_id"]},
          handler: :list
        },
        "responses_get" => {
          description: "Get a specific response",
          inputSchema: {
            type: "object",
            properties: {run_id: {type: "integer"}, id: {type: "integer"}},
            required: ["run_id", "id"]
          },
          handler: :get
        }
      }.freeze

      def self.definitions
        TOOLS.map { |name, config| {name: name, description: config[:description], inputSchema: config[:inputSchema]} }
      end

      def self.call(name, arguments)
        tool = TOOLS.fetch(name)
        send(tool[:handler], arguments)
      end

      def self.list(args)
        run = Run.find(args["run_id"])
        text_result(run.responses.includes(:reviews).map(&:as_json))
      end

      def self.get(args)
        run = Run.find(args["run_id"])
        text_result(run.responses.find(args["id"]).as_json)
      end

      def self.text_result(data)
        text = data.is_a?(String) ? data : data.to_json
        {content: [{type: "text", text: text}]}
      end
    end
  end
end
```

- [ ] **Step 4: Register in dispatcher**

Update `app/services/completion_kit/mcp_dispatcher.rb`:

```ruby
def self.tool_definitions
  McpTools::Prompts.definitions + McpTools::Runs.definitions + McpTools::Responses.definitions
end

def self.call_tool(name, arguments)
  case name
  when /\Aprompts_/  then McpTools::Prompts.call(name, arguments)
  when /\Aruns_/     then McpTools::Runs.call(name, arguments)
  when /\Aresponses_/ then McpTools::Responses.call(name, arguments)
  else raise MethodNotFound, "Unknown tool: #{name}"
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/responses_spec.rb`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add app/services/completion_kit/mcp_tools/responses.rb app/services/completion_kit/mcp_dispatcher.rb spec/services/completion_kit/mcp_tools/responses_spec.rb
git commit -m "feat: add MCP response tools"
```

---

### Task 5: Dataset tools

**Files:**
- Create: `app/services/completion_kit/mcp_tools/datasets.rb`
- Create: `spec/services/completion_kit/mcp_tools/datasets_spec.rb`
- Modify: `app/services/completion_kit/mcp_dispatcher.rb`

- [ ] **Step 1: Write the failing tool unit tests**

```ruby
# spec/services/completion_kit/mcp_tools/datasets_spec.rb
require "rails_helper"

RSpec.describe CompletionKit::McpTools::Datasets do
  describe ".definitions" do
    it "returns 5 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(5)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        datasets_list datasets_get datasets_create datasets_update datasets_delete
      ])
    end
  end

  describe ".call" do
    let!(:dataset) { create(:completion_kit_dataset, name: "Test DS") }

    it "lists datasets" do
      result = described_class.call("datasets_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("Test DS")
    end

    it "gets a dataset by id" do
      result = described_class.call("datasets_get", {"id" => dataset.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(dataset.id)
    end

    it "creates a dataset" do
      result = described_class.call("datasets_create", {"name" => "New", "csv_data" => "col1\nval1"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("New")
    end

    it "updates a dataset" do
      result = described_class.call("datasets_update", {"id" => dataset.id, "name" => "Updated"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Updated")
    end

    it "deletes a dataset" do
      result = described_class.call("datasets_delete", {"id" => dataset.id})
      expect(result[:content].first[:text]).to include("deleted")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/datasets_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement the datasets tools module**

```ruby
# app/services/completion_kit/mcp_tools/datasets.rb
module CompletionKit
  module McpTools
    module Datasets
      TOOLS = {
        "datasets_list" => {
          description: "List all datasets",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "datasets_get" => {
          description: "Get a dataset by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "datasets_create" => {
          description: "Create a dataset with CSV data",
          inputSchema: {
            type: "object",
            properties: {name: {type: "string"}, csv_data: {type: "string"}},
            required: ["name", "csv_data"]
          },
          handler: :create
        },
        "datasets_update" => {
          description: "Update a dataset",
          inputSchema: {
            type: "object",
            properties: {id: {type: "integer"}, name: {type: "string"}, csv_data: {type: "string"}},
            required: ["id"]
          },
          handler: :update
        },
        "datasets_delete" => {
          description: "Delete a dataset",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        }
      }.freeze

      def self.definitions
        TOOLS.map { |name, config| {name: name, description: config[:description], inputSchema: config[:inputSchema]} }
      end

      def self.call(name, arguments)
        tool = TOOLS.fetch(name)
        send(tool[:handler], arguments)
      end

      def self.list(_args)
        text_result(Dataset.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(Dataset.find(args["id"]).as_json)
      end

      def self.create(args)
        dataset = Dataset.new(args.slice("name", "csv_data"))
        if dataset.save
          text_result(dataset.as_json)
        else
          error_result(dataset.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        dataset = Dataset.find(args["id"])
        if dataset.update(args.except("id").slice("name", "csv_data"))
          text_result(dataset.as_json)
        else
          error_result(dataset.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        Dataset.find(args["id"]).destroy!
        text_result("Dataset #{args["id"]} deleted")
      end

      def self.text_result(data)
        text = data.is_a?(String) ? data : data.to_json
        {content: [{type: "text", text: text}]}
      end

      def self.error_result(message)
        {content: [{type: "text", text: message}], isError: true}
      end
    end
  end
end
```

- [ ] **Step 4: Register in dispatcher**

Update `app/services/completion_kit/mcp_dispatcher.rb` — add `McpTools::Datasets.definitions` to `tool_definitions` and `when /\Adatasets_/ then McpTools::Datasets.call(name, arguments)` to `call_tool`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/datasets_spec.rb`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add app/services/completion_kit/mcp_tools/datasets.rb app/services/completion_kit/mcp_dispatcher.rb spec/services/completion_kit/mcp_tools/datasets_spec.rb
git commit -m "feat: add MCP dataset tools"
```

---

### Task 6: Metric tools

**Files:**
- Create: `app/services/completion_kit/mcp_tools/metrics.rb`
- Create: `spec/services/completion_kit/mcp_tools/metrics_spec.rb`
- Modify: `app/services/completion_kit/mcp_dispatcher.rb`

- [ ] **Step 1: Write the failing tool unit tests**

```ruby
# spec/services/completion_kit/mcp_tools/metrics_spec.rb
require "rails_helper"

RSpec.describe CompletionKit::McpTools::Metrics do
  describe ".definitions" do
    it "returns 5 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(5)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        metrics_list metrics_get metrics_create metrics_update metrics_delete
      ])
    end
  end

  describe ".call" do
    let!(:metric) { create(:completion_kit_metric, name: "Accuracy") }

    it "lists metrics" do
      result = described_class.call("metrics_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("Accuracy")
    end

    it "gets a metric by id" do
      result = described_class.call("metrics_get", {"id" => metric.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(metric.id)
    end

    it "creates a metric" do
      result = described_class.call("metrics_create", {"name" => "Tone", "instruction" => "Evaluate tone"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Tone")
    end

    it "creates a metric with evaluation_steps and rubric_bands" do
      result = described_class.call("metrics_create", {
        "name" => "Full", "instruction" => "Test",
        "evaluation_steps" => ["Step 1", "Step 2"],
        "rubric_bands" => [{"stars" => 5, "description" => "Perfect"}]
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["evaluation_steps"]).to eq(["Step 1", "Step 2"])
    end

    it "updates a metric" do
      result = described_class.call("metrics_update", {"id" => metric.id, "name" => "Precision"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Precision")
    end

    it "deletes a metric" do
      result = described_class.call("metrics_delete", {"id" => metric.id})
      expect(result[:content].first[:text]).to include("deleted")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/metrics_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement the metrics tools module**

```ruby
# app/services/completion_kit/mcp_tools/metrics.rb
module CompletionKit
  module McpTools
    module Metrics
      TOOLS = {
        "metrics_list" => {
          description: "List all metrics",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "metrics_get" => {
          description: "Get a metric by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "metrics_create" => {
          description: "Create a metric with evaluation criteria",
          inputSchema: {
            type: "object",
            properties: {
              name: {type: "string"}, instruction: {type: "string"},
              evaluation_steps: {type: "array", items: {type: "string"}},
              rubric_bands: {type: "array", items: {type: "object", properties: {stars: {type: "integer"}, description: {type: "string"}}}}
            },
            required: ["name"]
          },
          handler: :create
        },
        "metrics_update" => {
          description: "Update a metric",
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, name: {type: "string"}, instruction: {type: "string"},
              evaluation_steps: {type: "array", items: {type: "string"}},
              rubric_bands: {type: "array", items: {type: "object", properties: {stars: {type: "integer"}, description: {type: "string"}}}}
            },
            required: ["id"]
          },
          handler: :update
        },
        "metrics_delete" => {
          description: "Delete a metric",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        }
      }.freeze

      def self.definitions
        TOOLS.map { |name, config| {name: name, description: config[:description], inputSchema: config[:inputSchema]} }
      end

      def self.call(name, arguments)
        tool = TOOLS.fetch(name)
        send(tool[:handler], arguments)
      end

      def self.list(_args)
        text_result(Metric.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(Metric.find(args["id"]).as_json)
      end

      def self.create(args)
        metric = Metric.new(args.slice("name", "instruction", "evaluation_steps", "rubric_bands"))
        if metric.save
          text_result(metric.as_json)
        else
          error_result(metric.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        metric = Metric.find(args["id"])
        if metric.update(args.except("id").slice("name", "instruction", "evaluation_steps", "rubric_bands"))
          text_result(metric.as_json)
        else
          error_result(metric.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        Metric.find(args["id"]).destroy!
        text_result("Metric #{args["id"]} deleted")
      end

      def self.text_result(data)
        text = data.is_a?(String) ? data : data.to_json
        {content: [{type: "text", text: text}]}
      end

      def self.error_result(message)
        {content: [{type: "text", text: message}], isError: true}
      end
    end
  end
end
```

- [ ] **Step 4: Register in dispatcher**

Add `McpTools::Metrics.definitions` and `when /\Ametrics_/ then McpTools::Metrics.call(name, arguments)` to dispatcher.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/metrics_spec.rb`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add app/services/completion_kit/mcp_tools/metrics.rb app/services/completion_kit/mcp_dispatcher.rb spec/services/completion_kit/mcp_tools/metrics_spec.rb
git commit -m "feat: add MCP metric tools"
```

---

### Task 7: Criteria tools

**Files:**
- Create: `app/services/completion_kit/mcp_tools/criteria.rb`
- Create: `spec/services/completion_kit/mcp_tools/criteria_spec.rb`
- Modify: `app/services/completion_kit/mcp_dispatcher.rb`

- [ ] **Step 1: Write the failing tool unit tests**

```ruby
# spec/services/completion_kit/mcp_tools/criteria_spec.rb
require "rails_helper"

RSpec.describe CompletionKit::McpTools::Criteria do
  describe ".definitions" do
    it "returns 5 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(5)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        criteria_list criteria_get criteria_create criteria_update criteria_delete
      ])
    end
  end

  describe ".call" do
    let!(:criteria) { create(:completion_kit_criteria, name: "Quality") }

    it "lists criteria" do
      result = described_class.call("criteria_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("Quality")
    end

    it "gets a criteria by id" do
      result = described_class.call("criteria_get", {"id" => criteria.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(criteria.id)
    end

    it "creates a criteria" do
      result = described_class.call("criteria_create", {"name" => "New Criteria"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("New Criteria")
    end

    it "creates a criteria with metric_ids" do
      metric = create(:completion_kit_metric)
      result = described_class.call("criteria_create", {"name" => "With Metrics", "metric_ids" => [metric.id]})
      content = JSON.parse(result[:content].first[:text])
      expect(content["metric_ids"]).to eq([metric.id])
    end

    it "updates a criteria" do
      result = described_class.call("criteria_update", {"id" => criteria.id, "name" => "Updated"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Updated")
    end

    it "deletes a criteria" do
      result = described_class.call("criteria_delete", {"id" => criteria.id})
      expect(result[:content].first[:text]).to include("deleted")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/criteria_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement the criteria tools module**

```ruby
# app/services/completion_kit/mcp_tools/criteria.rb
module CompletionKit
  module McpTools
    module Criteria
      TOOLS = {
        "criteria_list" => {
          description: "List all criteria",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "criteria_get" => {
          description: "Get a criteria by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "criteria_create" => {
          description: "Create a criteria grouping metrics",
          inputSchema: {
            type: "object",
            properties: {
              name: {type: "string"}, description: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}}
            },
            required: ["name"]
          },
          handler: :create
        },
        "criteria_update" => {
          description: "Update a criteria",
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, name: {type: "string"}, description: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}}
            },
            required: ["id"]
          },
          handler: :update
        },
        "criteria_delete" => {
          description: "Delete a criteria",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        }
      }.freeze

      def self.definitions
        TOOLS.map { |name, config| {name: name, description: config[:description], inputSchema: config[:inputSchema]} }
      end

      def self.call(name, arguments)
        tool = TOOLS.fetch(name)
        send(tool[:handler], arguments)
      end

      def self.list(_args)
        text_result(CompletionKit::Criteria.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(CompletionKit::Criteria.find(args["id"]).as_json)
      end

      def self.create(args)
        criteria = CompletionKit::Criteria.new(args.slice("name", "description"))
        if criteria.save
          replace_metric_memberships(criteria, args["metric_ids"])
          text_result(criteria.reload.as_json)
        else
          error_result(criteria.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        criteria = CompletionKit::Criteria.find(args["id"])
        if criteria.update(args.except("id", "metric_ids").slice("name", "description"))
          replace_metric_memberships(criteria, args["metric_ids"]) if args.key?("metric_ids")
          text_result(criteria.reload.as_json)
        else
          error_result(criteria.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        CompletionKit::Criteria.find(args["id"]).destroy!
        text_result("Criteria #{args["id"]} deleted")
      end

      def self.text_result(data)
        text = data.is_a?(String) ? data : data.to_json
        {content: [{type: "text", text: text}]}
      end

      def self.error_result(message)
        {content: [{type: "text", text: message}], isError: true}
      end

      def self.replace_metric_memberships(criteria, metric_ids)
        return unless metric_ids
        criteria.criteria_memberships.delete_all
        Array(metric_ids).reject(&:blank?).each_with_index do |metric_id, index|
          criteria.criteria_memberships.create!(metric_id: metric_id, position: index + 1)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Register in dispatcher**

Add `McpTools::Criteria.definitions` and `when /\Acriteria_/ then McpTools::Criteria.call(name, arguments)` to dispatcher.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/criteria_spec.rb`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add app/services/completion_kit/mcp_tools/criteria.rb app/services/completion_kit/mcp_dispatcher.rb spec/services/completion_kit/mcp_tools/criteria_spec.rb
git commit -m "feat: add MCP criteria tools"
```

---

### Task 8: Provider credential tools

**Files:**
- Create: `app/services/completion_kit/mcp_tools/provider_credentials.rb`
- Create: `spec/services/completion_kit/mcp_tools/provider_credentials_spec.rb`
- Modify: `app/services/completion_kit/mcp_dispatcher.rb`

- [ ] **Step 1: Write the failing tool unit tests**

```ruby
# spec/services/completion_kit/mcp_tools/provider_credentials_spec.rb
require "rails_helper"

RSpec.describe CompletionKit::McpTools::ProviderCredentials do
  describe ".definitions" do
    it "returns 5 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(5)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        provider_credentials_list provider_credentials_get
        provider_credentials_create provider_credentials_update provider_credentials_delete
      ])
    end
  end

  describe ".call" do
    let!(:credential) { create(:completion_kit_provider_credential, provider: "openai") }

    it "lists provider credentials" do
      result = described_class.call("provider_credentials_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["provider"]).to eq("openai")
    end

    it "does not expose api_key in list" do
      result = described_class.call("provider_credentials_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first).not_to have_key("api_key")
    end

    it "gets a credential by id" do
      result = described_class.call("provider_credentials_get", {"id" => credential.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(credential.id)
    end

    it "creates a credential" do
      result = described_class.call("provider_credentials_create", {
        "provider" => "anthropic", "api_key" => "sk-test-123"
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["provider"]).to eq("anthropic")
      expect(content).not_to have_key("api_key")
    end

    it "updates a credential" do
      result = described_class.call("provider_credentials_update", {
        "id" => credential.id, "api_endpoint" => "https://custom.api"
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["api_endpoint"]).to eq("https://custom.api")
    end

    it "deletes a credential" do
      result = described_class.call("provider_credentials_delete", {"id" => credential.id})
      expect(result[:content].first[:text]).to include("deleted")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/provider_credentials_spec.rb`
Expected: FAIL

- [ ] **Step 3: Implement the provider credentials tools module**

```ruby
# app/services/completion_kit/mcp_tools/provider_credentials.rb
module CompletionKit
  module McpTools
    module ProviderCredentials
      TOOLS = {
        "provider_credentials_list" => {
          description: "List all provider credentials (API keys are not exposed)",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "provider_credentials_get" => {
          description: "Get a provider credential by ID (API key is not exposed)",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "provider_credentials_create" => {
          description: "Create a provider credential",
          inputSchema: {
            type: "object",
            properties: {
              provider: {type: "string", enum: ["openai", "anthropic", "llama"]},
              api_key: {type: "string"},
              api_endpoint: {type: "string"}
            },
            required: ["provider", "api_key"]
          },
          handler: :create
        },
        "provider_credentials_update" => {
          description: "Update a provider credential",
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, provider: {type: "string"},
              api_key: {type: "string"}, api_endpoint: {type: "string"}
            },
            required: ["id"]
          },
          handler: :update
        },
        "provider_credentials_delete" => {
          description: "Delete a provider credential",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        }
      }.freeze

      def self.definitions
        TOOLS.map { |name, config| {name: name, description: config[:description], inputSchema: config[:inputSchema]} }
      end

      def self.call(name, arguments)
        tool = TOOLS.fetch(name)
        send(tool[:handler], arguments)
      end

      def self.list(_args)
        text_result(ProviderCredential.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(ProviderCredential.find(args["id"]).as_json)
      end

      def self.create(args)
        credential = ProviderCredential.new(args.slice("provider", "api_key", "api_endpoint"))
        if credential.save
          text_result(credential.as_json)
        else
          error_result(credential.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        credential = ProviderCredential.find(args["id"])
        if credential.update(args.except("id").slice("provider", "api_key", "api_endpoint"))
          text_result(credential.as_json)
        else
          error_result(credential.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        ProviderCredential.find(args["id"]).destroy!
        text_result("Provider credential #{args["id"]} deleted")
      end

      def self.text_result(data)
        text = data.is_a?(String) ? data : data.to_json
        {content: [{type: "text", text: text}]}
      end

      def self.error_result(message)
        {content: [{type: "text", text: message}], isError: true}
      end
    end
  end
end
```

- [ ] **Step 4: Register in dispatcher (final version)**

Update `app/services/completion_kit/mcp_dispatcher.rb` to its final form:

```ruby
def self.tool_definitions
  McpTools::Prompts.definitions +
    McpTools::Runs.definitions +
    McpTools::Responses.definitions +
    McpTools::Datasets.definitions +
    McpTools::Metrics.definitions +
    McpTools::Criteria.definitions +
    McpTools::ProviderCredentials.definitions
end

def self.call_tool(name, arguments)
  case name
  when /\Aprompts_/              then McpTools::Prompts.call(name, arguments)
  when /\Aruns_/                 then McpTools::Runs.call(name, arguments)
  when /\Aresponses_/            then McpTools::Responses.call(name, arguments)
  when /\Adatasets_/             then McpTools::Datasets.call(name, arguments)
  when /\Ametrics_/              then McpTools::Metrics.call(name, arguments)
  when /\Acriteria_/             then McpTools::Criteria.call(name, arguments)
  when /\Aprovider_credentials_/ then McpTools::ProviderCredentials.call(name, arguments)
  else raise MethodNotFound, "Unknown tool: #{name}"
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/provider_credentials_spec.rb`
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add app/services/completion_kit/mcp_tools/provider_credentials.rb app/services/completion_kit/mcp_dispatcher.rb spec/services/completion_kit/mcp_tools/provider_credentials_spec.rb
git commit -m "feat: add MCP provider credential tools"
```

---

### Task 9: Dispatcher unit tests

**Files:**
- Create: `spec/services/completion_kit/mcp_dispatcher_spec.rb`

- [ ] **Step 1: Write dispatcher unit tests**

```ruby
# spec/services/completion_kit/mcp_dispatcher_spec.rb
require "rails_helper"

RSpec.describe CompletionKit::McpDispatcher do
  describe ".initialize_session" do
    it "returns protocol version and server info" do
      result = described_class.initialize_session
      expect(result[:protocolVersion]).to eq("2025-03-26")
      expect(result[:serverInfo][:name]).to eq("CompletionKit")
      expect(result[:capabilities][:tools]).to eq({listChanged: false})
    end

    it "returns a session_id and caches it" do
      result = described_class.initialize_session
      expect(result[:session_id]).to be_present
      expect(Rails.cache.exist?("mcp_session:#{result[:session_id]}")).to be true
    end
  end

  describe ".dispatch" do
    it "returns tool definitions for tools/list" do
      result = described_class.dispatch("tools/list", nil)
      expect(result[:tools]).to be_an(Array)
      expect(result[:tools].length).to eq(36)
      expect(result[:tools].first).to have_key(:name)
      expect(result[:tools].first).to have_key(:description)
      expect(result[:tools].first).to have_key(:inputSchema)
    end

    it "raises MethodNotFound for unknown methods" do
      expect { described_class.dispatch("unknown/method", nil) }
        .to raise_error(described_class::MethodNotFound, /Method not found/)
    end

    it "raises MethodNotFound for unknown tools" do
      expect { described_class.dispatch("tools/call", {"name" => "bogus_tool", "arguments" => {}}) }
        .to raise_error(described_class::MethodNotFound, /Unknown tool/)
    end

    it "calls a tool and returns result" do
      create(:completion_kit_prompt, name: "Test")
      result = described_class.dispatch("tools/call", {"name" => "prompts_list", "arguments" => {}})
      expect(result[:content]).to be_an(Array)
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("Test")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/mcp_dispatcher_spec.rb`
Expected: all pass

- [ ] **Step 3: Commit**

```bash
git add spec/services/completion_kit/mcp_dispatcher_spec.rb
git commit -m "test: add MCP dispatcher unit tests"
```

---

### Task 10: Integration tests for tools/call

**Files:**
- Modify: `spec/requests/completion_kit/mcp_spec.rb`

- [ ] **Step 1: Add integration tests for tool calls through HTTP**

Append to `spec/requests/completion_kit/mcp_spec.rb`:

```ruby
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

  it "handles notifications/initialized as no-op" do
    post mcp_path, params: {jsonrpc: "2.0", method: "notifications/initialized"}.to_json, headers: session_headers
    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 2: Run all MCP tests**

Run: `bundle exec rspec spec/requests/completion_kit/mcp_spec.rb`
Expected: all pass

- [ ] **Step 3: Commit**

```bash
git add spec/requests/completion_kit/mcp_spec.rb
git commit -m "test: add MCP integration tests for tool calls"
```

---

### Task 11: Full suite verification

- [ ] **Step 1: Run the full test suite**

Run: `bundle exec rspec`
Expected: all pass, 100% line and branch coverage

- [ ] **Step 2: Fix any coverage gaps**

If coverage is below 100%, identify uncovered lines and add tests.

- [ ] **Step 3: Final commit and push**

```bash
git push
```

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

    it "handles nil params for tools/call" do
      expect { described_class.dispatch("tools/call", nil) }
        .to raise_error(described_class::MethodNotFound)
    end

    it "raises MethodNotFound for unknown methods" do
      expect { described_class.dispatch("unknown/method", nil) }
        .to raise_error(described_class::MethodNotFound, /Method not found/)
    end

    it "raises MethodNotFound for unknown tools" do
      expect { described_class.dispatch("tools/call", {"name" => "bogus_tool", "arguments" => {}}) }
        .to raise_error(described_class::MethodNotFound, /Unknown tool/)
    end

    it "calls a prompt tool through dispatcher" do
      create(:completion_kit_prompt, name: "Test")
      result = described_class.dispatch("tools/call", {"name" => "prompts_list", "arguments" => {}})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("Test")
    end

    it "calls a run tool through dispatcher" do
      prompt = create(:completion_kit_prompt)
      create(:completion_kit_run, prompt: prompt, name: "R1")
      result = described_class.dispatch("tools/call", {"name" => "runs_list", "arguments" => {}})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("R1")
    end

    it "calls a response tool through dispatcher" do
      prompt = create(:completion_kit_prompt)
      run = create(:completion_kit_run, prompt: prompt)
      create(:completion_kit_response, run: run)
      result = described_class.dispatch("tools/call", {"name" => "responses_list", "arguments" => {"run_id" => run.id}})
      content = JSON.parse(result[:content].first[:text])
      expect(content).to be_an(Array)
    end

    it "calls a dataset tool through dispatcher" do
      create(:completion_kit_dataset, name: "DS")
      result = described_class.dispatch("tools/call", {"name" => "datasets_list", "arguments" => {}})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("DS")
    end

    it "calls a metric tool through dispatcher" do
      create(:completion_kit_metric, name: "M1")
      result = described_class.dispatch("tools/call", {"name" => "metrics_list", "arguments" => {}})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("M1")
    end

    it "calls a criteria tool through dispatcher" do
      create(:completion_kit_criteria, name: "C1")
      result = described_class.dispatch("tools/call", {"name" => "criteria_list", "arguments" => {}})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("C1")
    end

    it "calls a provider_credentials tool through dispatcher" do
      create(:completion_kit_provider_credential, provider: "openai")
      result = described_class.dispatch("tools/call", {"name" => "provider_credentials_list", "arguments" => {}})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["provider"]).to eq("openai")
    end
  end
end

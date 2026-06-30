require "rails_helper"

RSpec.describe CompletionKit::McpDispatcher do
  describe ".initialize_session" do
    it "returns protocol version and server info" do
      result = described_class.initialize_session
      expect(result[:protocolVersion]).to eq("2025-03-26")
      expect(result[:serverInfo][:name]).to eq("CompletionKit")
      expect(result[:capabilities][:tools]).to eq({listChanged: false})
    end

    it "returns a session_id and records an active session" do
      result = described_class.initialize_session
      expect(result[:session_id]).to be_present
      expect(CompletionKit::McpSession.active?(result[:session_id])).to be true
    end
  end

  describe ".dispatch" do
    it "returns tool definitions for tools/list" do
      result = described_class.dispatch("tools/list", nil)
      expect(result[:tools]).to be_an(Array)
      expect(result[:tools].length).to eq(50)
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

    it "routes the promptfoo_import tool through the dispatcher" do
      result = described_class.dispatch("tools/call", { "name" => "promptfoo_import", "arguments" => { "config" => "prompts:\n  - \"Hi {{x}}\"\n" } })
      expect(result[:content].first[:text]).to include("Imported prompt 1")
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

    it "calls a metric_groups tool through dispatcher" do
      create(:completion_kit_metric_group, name: "C1")
      result = described_class.dispatch("tools/call", {"name" => "metric_groups_list", "arguments" => {}})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("C1")
    end

    it "calls a provider_credentials tool through dispatcher" do
      create(:completion_kit_provider_credential, provider: "openai")
      result = described_class.dispatch("tools/call", {"name" => "provider_credentials_list", "arguments" => {}})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["provider"]).to eq("openai")
    end

    it "calls an agreements tool through dispatcher" do
      result = described_class.dispatch("tools/call", {"name" => "agreements_list", "arguments" => {}})
      content = JSON.parse(result[:content].first[:text])
      expect(content).to eq([])
    end

    it "calls a metric_versions tool through dispatcher" do
      metric = create(:completion_kit_metric)
      CompletionKit::MetricVersion.ensure_current_for(metric)
      result = described_class.dispatch("tools/call", {"name" => "metric_versions_list", "arguments" => {"metric_id" => metric.id}})
      content = JSON.parse(result[:content].first[:text])
      expect(content.size).to eq(1)
      expect(content.first["metric_id"]).to eq(metric.id)
    end

    it "calls a judges tool through dispatcher" do
      metric = create(:completion_kit_metric)
      a = CompletionKit::MetricVersion.ensure_current_for(metric)
      b = CompletionKit::MetricVersion.create!(metric: metric, instruction: "draft", current: false, state: "draft", source: "edit")
      result = described_class.dispatch("tools/call", {"name" => "judges_compare", "arguments" => {"metric_id" => metric.id, "metric_version_a_id" => a.id, "metric_version_b_id" => b.id}})
      payload = JSON.parse(result[:content].first[:text])
      expect(payload["metric_id"]).to eq(metric.id)
    end
  end
end

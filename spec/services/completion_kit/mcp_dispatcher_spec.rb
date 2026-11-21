require "rails_helper"

RSpec.describe CompletionKit::McpDispatcher do
  describe ".initialize_session" do
    it "returns protocol version and server info" do
      result = described_class.initialize_session
      expect(result[:protocolVersion]).to eq("2025-06-18")
      expect(result[:serverInfo][:name]).to eq("CompletionKit")
      expect(result[:capabilities][:tools]).to eq({listChanged: false})
    end

    it "returns a fresh random session_id without touching the database" do
      queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| queries << payload[:sql] }
      first = described_class.initialize_session[:session_id]
      second = described_class.initialize_session[:session_id]
      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(first).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      expect(second).not_to eq(first)
      expect(queries).to be_empty
    end
  end

  describe ".dispatch" do
    it "returns tool definitions for tools/list" do
      result = described_class.dispatch("tools/list", nil)
      expect(result[:tools]).to be_an(Array)
      expect(result[:tools].length).to eq(53)
      expect(result[:tools].first).to have_key(:name)
      expect(result[:tools].first).to have_key(:description)
      expect(result[:tools].first).to have_key(:inputSchema)
    end

    describe "tool annotations" do
      let(:tools) { described_class.dispatch("tools/list", nil)[:tools] }
      let(:destructive_names) do
        %w[prompts_create prompts_update prompts_delete prompts_publish runs_update runs_delete runs_generate runs_regrade
           datasets_update datasets_delete metrics_update metrics_delete metric_groups_update metric_groups_delete
           metric_versions_publish metric_versions_dismiss provider_credentials_update provider_credentials_delete
           tags_update tags_delete agreements_create]
      end
      let(:open_world_names) { %w[datasets_create_from_url provider_credentials_create provider_credentials_update] }

      it "declares readOnlyHint, destructiveHint and openWorldHint as booleans on every tool" do
        tools.each do |tool|
          hints = tool[:annotations]
          expect(hints).to be_a(Hash), "#{tool[:name]} has no annotations"
          %i[readOnlyHint destructiveHint openWorldHint].each do |key|
            expect([true, false]).to include(hints[key]), "#{tool[:name]} #{key} is not a boolean"
          end
        end
      end

      it "never marks a read-only tool destructive" do
        tools.select { |t| t[:annotations][:readOnlyHint] }.each do |tool|
          expect(tool[:annotations][:destructiveHint]).to be(false), tool[:name]
        end
      end

      it "matches the agreed classification" do
        expect(tools.select { |t| t[:annotations][:destructiveHint] }.map { |t| t[:name] }).to match_array(destructive_names)
        expect(tools.select { |t| t[:annotations][:openWorldHint] }.map { |t| t[:name] }).to match_array(open_world_names)
      end

      it "keeps every description free of em dashes" do
        tools.each { |tool| expect(tool[:description]).not_to include("\u2014"), tool[:name] }
      end
    end

    it "matches the tool count the gemspec advertises on the public gem page" do
      gemspec_path = File.expand_path("../../../completion-kit.gemspec", __dir__)
      advertised = File.read(gemspec_path)[/MCP server with (\d+) tools/, 1]
      expect(advertised.to_i).to eq(described_class.dispatch("tools/list", nil)[:tools].length)
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
      expect(content["responses"]).to be_an(Array)
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

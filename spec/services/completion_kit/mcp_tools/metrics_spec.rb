require "rails_helper"

RSpec.describe CompletionKit::McpTools::Metrics do
  describe ".definitions" do
    it "returns 6 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(6)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        metrics_list metrics_get metrics_create metrics_update metrics_delete metrics_suggest_variants
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

    it "creates a metric with rubric_bands" do
      result = described_class.call("metrics_create", {
        "name" => "Full", "instruction" => "Test",
        "rubric_bands" => [{"stars" => 5, "description" => "Perfect"}]
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["rubric_bands"].find { |b| b["stars"] == 5 }["description"]).to eq("Perfect")
    end

    it "creates a check metric with metric_type and check_config" do
      result = described_class.call("metrics_create", {
        "name" => "Contains OK", "metric_type" => "check",
        "check_config" => {"check_kind" => "contains", "target" => "response_text", "value" => "OK"}
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["metric_type"]).to eq("check")
      expect(content["check_config"]).to include("value" => "OK")
    end

    it "updates a check metric's check_config" do
      check = create(:completion_kit_metric, :check)
      result = described_class.call("metrics_update", {
        "id" => check.id,
        "check_config" => {"check_kind" => "contains", "target" => "response_text", "value" => "done"}
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["check_config"]).to include("value" => "done")
    end

    it "advertises metric_type and check_config on the create and update schemas" do
      %w[metrics_create metrics_update].each do |tool|
        schema = described_class::TOOLS[tool][:inputSchema]
        expect(schema[:properties]).to have_key(:metric_type)
        expect(schema[:properties][:metric_type][:enum]).to include("check")
        expect(schema[:properties]).to have_key(:check_config)
      end
    end

    it "advertises the compare_to source and expected_path field for grading against expected" do
      schema = described_class::CHECK_CONFIG_SCHEMA
      expect(schema[:properties][:compare_to][:enum]).to match_array(%w[constant expected])
      expect(schema[:properties]).to have_key(:expected_path)
      expect(described_class::CHECK_CONFIG_HINT).to include("compare_to")
    end

    it "says a missing case_sensitive matches case-insensitively on text, regex and list checks" do
      sentence = "A check with no case_sensitive matches case-insensitively, regex and list_overlap included"
      expect(described_class::CHECK_CONFIG_HINT).to include(sentence)
      expect(described_class::CHECK_CONFIG_SCHEMA[:properties][:case_sensitive][:description]).to include(sentence)
      %w[metrics_create metrics_update].each do |tool|
        expect(described_class::TOOLS[tool][:description]).to include(sentence)
      end
    end

    it "creates a comparison check that grades against each row's expected_output" do
      result = described_class.call("metrics_create", {
        "name" => "VIN ground truth", "metric_type" => "check",
        "check_config" => {"check_kind" => "equals", "target" => "json_path", "target_path" => "vin", "compare_to" => "expected", "expected_path" => "vin"}
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["check_config"]).to include("check_kind" => "equals", "compare_to" => "expected", "expected_path" => "vin")
    end

    def create_check(name, config)
      result = described_class.call("metrics_create", {"name" => name, "metric_type" => "check", "check_config" => config})
      expect(result[:isError]).to be_falsey, result[:content].first[:text]
      JSON.parse(result[:content].first[:text])["check_config"]
    end

    it "creates a list_overlap check from a list value with score_by and min" do
      config = create_check("Codes", {"check_kind" => "list_overlap", "target" => "json_path", "target_path" => "optionCodes",
                                      "value" => %w[A B], "score_by" => "precision", "min" => 0.5})

      expect(config).to include("value" => %w[A B], "score_by" => "precision", "min" => 0.5)
    end

    it "creates a numeric_bounds check" do
      config = create_check("Confidence", {"check_kind" => "numeric_bounds", "target" => "json_path", "target_path" => "$.vin.confidence", "min" => 0.8})

      expect(config).to include("check_kind" => "numeric_bounds", "min" => 0.8)
    end

    it "creates a numeric_equals check with a numeric value and a tolerance" do
      config = create_check("Mileage", {"check_kind" => "numeric_equals", "target" => "response_text", "value" => 82_000, "tolerance" => "2%"})

      expect(config).to include("value" => 82_000, "tolerance" => "2%")
    end

    it "creates a json_path_equals check graded against each row's answer key" do
      config = create_check("Trim", {"check_kind" => "json_path_equals", "target" => "response_text", "json_path" => "trim",
                                     "compare_to" => "expected", "expected_path" => "trim"})

      expect(config).to include("compare_to" => "expected", "expected_path" => "trim")
    end

    it "refuses a list value on a rule that compares one value" do
      result = described_class.call("metrics_create", {"name" => "Contains list", "metric_type" => "check",
                                                       "check_config" => {"check_kind" => "contains", "target" => "response_text", "value" => %w[foo bar]}})

      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to eq('Check needs "Text to look for" to be a single value, since only list_overlap takes a list')
      expect(CompletionKit::Metric.where(name: "Contains list")).to be_empty
    end

    it "refuses a list value when updating a rule that compares one value" do
      check = create(:completion_kit_metric, :check, check_config: {"check_kind" => "numeric_equals", "target" => "response_text", "value" => 5})
      result = described_class.call("metrics_update", {"id" => check.id,
                                                       "check_config" => {"check_kind" => "numeric_equals", "target" => "response_text", "value" => [5, 6]}})

      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to include("only list_overlap takes a list")
      expect(check.reload.check_config["value"]).to eq(5)
    end

    it "advertises a value that may be text, a number or a list" do
      value = described_class::CHECK_CONFIG_SCHEMA[:properties][:value]
      expect(value[:type]).to match_array(%w[string number array])
      expect(value[:items][:type]).to match_array(%w[string number])
    end

    it "updates a metric" do
      result = described_class.call("metrics_update", {"id" => metric.id, "name" => "Precision"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Precision")
    end

    it "returns error on invalid create" do
      result = described_class.call("metrics_create", {"name" => ""})
      expect(result[:isError]).to be true
    end

    it "returns error on invalid update" do
      result = described_class.call("metrics_update", {"id" => metric.id, "name" => ""})
      expect(result[:isError]).to be true
    end

    it "deletes a metric" do
      result = described_class.call("metrics_delete", {"id" => metric.id})
      expect(result[:content].first[:text]).to include("deleted")
    end

    it "round-trips tag_names on metrics_create with auto-create" do
      expect do
        described_class.call("metrics_create",
          {"name" => "T", "instruction" => "x", "tag_names" => ["new"]})
      end.to change(CompletionKit::Tag, :count).by(1)
      found = CompletionKit::Metric.find_by!(name: "T")
      expect(found.tag_names).to eq(["new"])
    end

    it "replaces tag_names on metrics_update" do
      metric.update!(tag_names: ["a", "b"])
      described_class.call("metrics_update", {"id" => metric.id, "tag_names" => ["c"]})
      expect(metric.reload.tag_names).to eq(["c"])
    end
  end
end

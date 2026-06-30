require "rails_helper"

RSpec.describe "Check metric authoring", type: :request do
  let(:base_path) { "/completion_kit/metrics" }

  describe "web create" do
    it "persists metric_type and check_config" do
      post base_path, params: { metric: { name: "JSON valid", metric_type: "check",
                                          check_config: { check_kind: "valid_json", target: "response_text" } } }

      metric = CompletionKit::Metric.find_by(name: "JSON valid")
      expect(metric.metric_type).to eq("check")
      expect(metric.check_config).to include("check_kind" => "valid_json", "target" => "response_text")
    end

    it "coerces numeric and boolean check_config fields from the form" do
      post base_path, params: { metric: { name: "Contains exact", metric_type: "check",
                                          check_config: { check_kind: "contains", target: "response_text", value: "OK", case_sensitive: "true" } } }

      config = CompletionKit::Metric.find_by(name: "Contains exact").check_config
      expect(config["case_sensitive"]).to be(true)
    end

    it "coerces length_bounds min and max to integers" do
      post base_path, params: { metric: { name: "Bounded", metric_type: "check",
                                          check_config: { check_kind: "length_bounds", target: "response_text", min: "2", max: "9" } } }

      config = CompletionKit::Metric.find_by(name: "Bounded").check_config
      expect(config["min"]).to eq(2)
      expect(config["max"]).to eq(9)
    end
  end

  describe "web update versioning" do
    it "drafts a new MetricVersion when editing check_config on a check that has reviews" do
      metric = create(:completion_kit_metric, :check)
      response_row = create(:completion_kit_response)
      create(:completion_kit_review, :check, response: response_row, metric: metric,
             metric_version: CompletionKit::MetricVersion.ensure_current_for(metric))

      expect do
        patch "#{base_path}/#{metric.id}", params: { metric: { check_config: { check_kind: "contains", target: "response_text", value: "ok" } } }
      end.to change(CompletionKit::MetricVersion.drafts, :count).by(1)
    end

    it "updates the metric and current version in place when there are no reviews" do
      metric = create(:completion_kit_metric, :check)
      CompletionKit::MetricVersion.ensure_current_for(metric)

      patch "#{base_path}/#{metric.id}", params: { metric: { check_config: { check_kind: "contains", target: "response_text", value: "done" } } }

      expect(metric.reload.check_config).to include("value" => "done")
      expect(CompletionKit::MetricVersion.current.find_by(metric_id: metric.id).check_config).to include("value" => "done")
      expect(CompletionKit::MetricVersion.drafts.where(metric_id: metric.id)).to be_empty
    end

    it "redirects without versioning when check_config is unchanged" do
      metric = create(:completion_kit_metric, :check, check_config: { "check_kind" => "valid_json", "target" => "response_text" })
      create(:completion_kit_review, :check, response: create(:completion_kit_response), metric: metric,
             metric_version: CompletionKit::MetricVersion.ensure_current_for(metric))

      expect do
        patch "#{base_path}/#{metric.id}", params: { metric: { check_config: { check_kind: "valid_json", target: "response_text" } } }
      end.not_to change(CompletionKit::MetricVersion.drafts, :count)
    end

    it "leaves the definition unchanged when only the name is edited" do
      metric = create(:completion_kit_metric, :check)
      CompletionKit::MetricVersion.ensure_current_for(metric)

      expect do
        patch "#{base_path}/#{metric.id}", params: { metric: { name: "Renamed Check" } }
      end.not_to change(CompletionKit::MetricVersion.drafts, :count)

      expect(metric.reload.name).to eq("Renamed Check")
    end

    it "updates check_config in place even when no current published version exists yet" do
      metric = create(:completion_kit_metric, :check)

      patch "#{base_path}/#{metric.id}", params: { metric: { check_config: { check_kind: "contains", target: "response_text", value: "x" } } }

      expect(metric.reload.check_config).to include("value" => "x")
    end

    it "locks metric_type once the metric is used in a run" do
      metric = create(:completion_kit_metric, :check)
      run = create(:completion_kit_run)
      run.run_metrics.create!(metric: metric, position: 1)

      patch "#{base_path}/#{metric.id}", params: { metric: { metric_type: "llm_judge" } }

      expect(metric.reload.metric_type).to eq("check")
    end
  end

  describe "starters" do
    it "adopts a check starter, copying metric_type and check_config" do
      post "#{base_path}/starters/valid_json"

      metric = CompletionKit::Metric.find_by(name: "Valid JSON")
      expect(metric.metric_type).to eq("check")
      expect(metric.check_config).to include("check_kind" => "valid_json")
    end
  end

  describe "API v1" do
    let(:token) { "test-api-token" }
    let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }

    before { CompletionKit.config.api_token = token }
    after { CompletionKit.instance_variable_set(:@config, nil) }

    it "creates a check metric" do
      post "/completion_kit/api/v1/metrics",
           params: { name: "API JSON", metric_type: "check", check_config: { check_kind: "valid_json", target: "response_text" } }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["metric_type"]).to eq("check")
    end

    it "updates check_config" do
      metric = create(:completion_kit_metric, :check)

      patch "/completion_kit/api/v1/metrics/#{metric.id}",
            params: { check_config: { check_kind: "contains", target: "response_text", value: "ok" } }.to_json,
            headers: headers

      expect(JSON.parse(response.body)["check_config"]).to include("value" => "ok")
    end
  end
end

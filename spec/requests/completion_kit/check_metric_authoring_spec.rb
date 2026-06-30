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

    it "coerces a numeric json_path_equals expected so it can match numeric JSON" do
      post base_path, params: { metric: { name: "Status code", metric_type: "check",
                                          check_config: { check_kind: "json_path_equals", target: "response_text", json_path: "code", expected: "200" } } }

      config = CompletionKit::Metric.find_by(name: "Status code").check_config
      expect(config["expected"]).to eq(200)
    end

    it "keeps a non-JSON json_path_equals expected as a string" do
      post base_path, params: { metric: { name: "Status word", metric_type: "check",
                                          check_config: { check_kind: "json_path_equals", target: "response_text", json_path: "state", expected: "active" } } }

      config = CompletionKit::Metric.find_by(name: "Status word").check_config
      expect(config["expected"]).to eq("active")
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

  describe "authoring views" do
    it "renders the metric-type chooser and an inline check builder on the new form" do
      get "#{base_path}/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Metric type")
      expect(response.body).to include("LLM judge (1-5)")
      expect(response.body).to include("Deterministic check")
      expect(response.body).to include('name="metric[check_config][check_kind]"')
      expect(response.body).to include('name="metric[check_config][target]"')
      CompletionKit::Checks::Registry.kinds.each do |kind|
        expect(response.body).to include(">#{kind}</option>")
      end
      CompletionKit::Checks::TargetResolver::TARGETS.each do |target|
        expect(response.body).to include(">#{target}</option>")
      end
      expect(response.body).to include("ck-rubric-builder")
    end

    it "creates a check through the inline builder fields" do
      expect do
        post base_path, params: { metric: { name: "Inline check", metric_type: "check",
                                            check_config: { check_kind: "valid_json", target: "response_text" } } }
      end.to change(CompletionKit::Metric, :count).by(1)

      metric = CompletionKit::Metric.find_by(name: "Inline check")
      expect(metric.check?).to be(true)
      expect(metric.check_config).to include("check_kind" => "valid_json")
    end

    it "renders the check builder prefilled and hides the chooser when editing a check" do
      metric = create(:completion_kit_metric, :check,
        check_config: { "check_kind" => "contains", "target" => "json_path", "target_path" => "data.field",
                        "value" => "TOKEN", "case_sensitive" => true, "multiline" => true, "trim" => true })

      get "#{base_path}/#{metric.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Metric type")
      expect(response.body).not_to include("ck-rubric-builder")
      expect(response.body).to include('type="hidden"')
      expect(response.body).to include('name="metric[metric_type]"')
      expect(response.body).to include('value="contains" selected')
      expect(response.body).to include('value="json_path" selected')
      expect(response.body).to include("data.field")
      expect(response.body).to include("TOKEN")
      expect(response.body.scan("checked").size).to be >= 3
    end

    it "shows the check spec instead of rubric stars on a check's show page" do
      metric = create(:completion_kit_metric, :check,
        check_config: { "check_kind" => "contains", "target" => "response_text",
                        "value" => "TOKEN", "case_sensitive" => true })

      get "#{base_path}/#{metric.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("contains")
      expect(response.body).to include("response_text")
      expect(response.body).to include("Value")
      expect(response.body).to include("TOKEN")
      expect(response.body).not_to include("ck-rubric-display")
    end

    it "tags each row in the index with a Judge or Check chip" do
      create(:completion_kit_metric, name: "Helpfulness")
      create(:completion_kit_metric, :check, name: "JSON shape")

      get base_path

      expect(response.body).to include(">Judge</span>")
      expect(response.body).to include(">Check</span>")
    end

    it "previews a check starter as a check spec, not a star rubric" do
      get "#{base_path}/starters/valid_json"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Valid JSON")
      expect(response.body).to include("valid_json")
      expect(response.body).to include("response_text")
      expect(response.body).not_to include("Judge instruction")
      expect(response.body).not_to include("ck-rubric-display")
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

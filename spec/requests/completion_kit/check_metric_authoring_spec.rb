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

    it "grades against the row's expected value and drops the constant value when compare_to is expected" do
      post base_path, params: { metric: { name: "VIN gold", metric_type: "check",
                                          check_config: { check_kind: "equals", target: "response_text",
                                                          compare_to: "expected", expected_path: "vin", value: "leftover" } } }

      config = CompletionKit::Metric.find_by(name: "VIN gold").check_config
      expect(config).to include("compare_to" => "expected", "expected_path" => "vin")
      expect(config).not_to have_key("value")
    end

    it "drops compare_to and expected_path when comparing to a constant" do
      post base_path, params: { metric: { name: "Constant contains", metric_type: "check",
                                          check_config: { check_kind: "contains", target: "response_text",
                                                          compare_to: "constant", expected_path: "vin", value: "OK" } } }

      config = CompletionKit::Metric.find_by(name: "Constant contains").check_config
      expect(config).to include("value" => "OK")
      expect(config).not_to have_key("compare_to")
      expect(config).not_to have_key("expected_path")
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

    it "keeps a decimal bound as a decimal rather than truncating it to zero" do
      post base_path, params: { metric: { name: "Confident", metric_type: "check",
                                          check_config: { check_kind: "numeric_bounds", target: "json_path",
                                                          target_path: "vin.confidence", min: "0.8" } } }

      config = CompletionKit::Metric.find_by(name: "Confident").check_config
      expect(config["min"]).to eq(0.8)
      expect(config["target_path"]).to eq("vin.confidence")
    end

    it "leaves a bound that is not a number alone so the model can reject it" do
      post base_path, params: { metric: { name: "Bad bound", metric_type: "check",
                                          check_config: { check_kind: "length_bounds", target: "response_text", min: "abc" } } }

      expect(CompletionKit::Metric.find_by(name: "Bad bound")).to be_nil
      expect(response.body).to include("must be numbers")
    end

    it "drops target_path when the check no longer reads the response JSON" do
      post base_path, params: { metric: { name: "Plain contains", metric_type: "check",
                                          check_config: { check_kind: "contains", target: "response_text",
                                                          target_path: "leftover", value: "OK" } } }

      config = CompletionKit::Metric.find_by(name: "Plain contains").check_config
      expect(config).not_to have_key("target_path")
    end

    it "drops the fields a previously chosen kind left behind in the hidden form inputs" do
      post base_path, params: { metric: { name: "Just a regex", metric_type: "check",
                                          check_config: { check_kind: "regex", target: "response_text", pattern: "ok",
                                                          value: "leftover", json_path: "leftover", min: "3",
                                                          case_sensitive: "false", trim: "false" } } }

      config = CompletionKit::Metric.find_by(name: "Just a regex").check_config
      expect(config).to include("pattern" => "ok", "case_sensitive" => false)
      expect(config.keys).not_to include("value", "json_path", "min", "trim")
    end

    it "stores an explicitly unchecked case_sensitive so a regex can be made case-insensitive" do
      post base_path, params: { metric: { name: "Loose regex", metric_type: "check",
                                          check_config: { check_kind: "regex", target: "response_text",
                                                          pattern: "ok", case_sensitive: "false" } } }

      expect(CompletionKit::Metric.find_by(name: "Loose regex").check_config["case_sensitive"]).to be(false)
    end

    it "persists a set_overlap check with its measure and threshold" do
      post base_path, params: { metric: { name: "Option codes", metric_type: "check",
                                          check_config: { check_kind: "set_overlap", target: "json_path",
                                                          target_path: "optionCodes", compare_to: "expected",
                                                          expected_path: "optionCodes", measure: "recall", min: "0.8" } } }

      config = CompletionKit::Metric.find_by(name: "Option codes").check_config
      expect(config).to include("measure" => "recall", "min" => 0.8, "compare_to" => "expected")
      expect(config).not_to have_key("value")
    end

    it "persists a numeric_equals check with its tolerance" do
      post base_path, params: { metric: { name: "Mileage", metric_type: "check",
                                          check_config: { check_kind: "numeric_equals", target: "json_path",
                                                          target_path: "mileage", compare_to: "expected",
                                                          expected_path: "mileage", tolerance: "0.02",
                                                          tolerance_mode: "relative" } } }

      config = CompletionKit::Metric.find_by(name: "Mileage").check_config
      expect(config).to include("tolerance" => 0.02, "tolerance_mode" => "relative")
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

    it "drops a stray rubric and instruction when creating a check" do
      post base_path, params: { metric: { name: "Check only", metric_type: "check",
                                          instruction: "should be ignored",
                                          rubric_bands: { "0" => { stars: "5", description: "great" } },
                                          check_config: { check_kind: "valid_json", target: "response_text" } } }

      metric = CompletionKit::Metric.find_by(name: "Check only")
      expect(metric.check?).to be(true)
      expect(metric.check_config).to include("check_kind" => "valid_json")
      expect(metric.rubric_bands).to be_blank
      expect(metric.instruction).to be_blank
    end

    it "drops a stray check_config when creating an llm_judge metric" do
      post base_path, params: { metric: { name: "Judge only", metric_type: "llm_judge",
                                          instruction: "Rate helpfulness",
                                          check_config: { check_kind: "valid_json", target: "response_text" } } }

      metric = CompletionKit::Metric.find_by(name: "Judge only")
      expect(metric.llm_judge?).to be(true)
      expect(metric.check_config).to be_blank
      expect(metric.rubric_bands).to be_present
      expect(metric.instruction).to eq("Rate helpfulness")
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

    it "adopts the answer-key starter as an equals check graded against expected" do
      post "#{base_path}/starters/matches_expected"

      metric = CompletionKit::Metric.find_by(name: "Matches the answer key")
      expect(metric.metric_type).to eq("check")
      expect(metric.check_config).to include("check_kind" => "equals", "compare_to" => "expected")
    end
  end

  describe "authoring views" do
    it "renders the metric-type chooser and a branded check builder with human labels on the new form" do
      get "#{base_path}/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Metric type")
      expect(response.body).to include("LLM judge (1-5)")
      expect(response.body).to include("Deterministic check")
      expect(response.body).to include('name="metric[check_config][check_kind]"')
      expect(response.body).to include('name="metric[check_config][target]"')
      expect(response.body).to include("data-ck-select")
      expect(response.body).to include('role="listbox"')
      expect(response.body).to include("Does not contain a phrase")
      expect(response.body).to include("Is valid JSON")
      expect(response.body).to include("The response text")
      expect(response.body).to include('data-ck-check-field="compare_to"')
      expect(response.body).to include('name="metric[check_config][compare_to]"')
      expect(response.body).to include("Each row's expected value")
      expect(response.body).to include('data-ck-check-field="expected_path"')
      expect(response.body).to include('name="metric[check_config][expected_path]"')
      expect(response.body).not_to include(">not_contains<")
      expect(response.body).not_to include(">response_text<")
      expect(response.body).to include("ck-rubric-builder")
    end

    it "explains the metric types in plain language on the new form" do
      get "#{base_path}/new"

      expect(response.body).to include("The judge gives each response 1 to 5 stars against your rubric. A check just passes or fails, with no AI.")
      expect(response.body).not_to include("ck-radio-info")
    end

    it "renders both editors on the new form with the check editor hidden by default" do
      get "#{base_path}/new"

      expect(response.body).to include('data-ck-metric-editor="llm_judge"')
      expect(response.body).to include('data-ck-metric-editor="check"')
      expect(response.body).to match(/data-ck-metric-editor="check"[^>]*hidden/)
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
      expect(response.body).to include('name="metric[check_config][check_kind]" value="contains"')
      expect(response.body).to include('name="metric[check_config][target]" value="json_path"')
      expect(response.body).to include("Contains a phrase")
      expect(response.body).to include("A value from the response JSON")
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
      expect(response.body).to include("Contains a phrase")
      expect(response.body).to include("The response text")
      expect(response.body).to include("Text to look for")
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
      expect(response.body).to include("Is valid JSON")
      expect(response.body).to include("The response text")
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

    it "creates a comparison check graded against each row's expected value" do
      post "/completion_kit/api/v1/metrics",
           params: { name: "VIN match", metric_type: "check",
                     check_config: { check_kind: "equals", target: "json_path", target_path: "vin", compare_to: "expected", expected_path: "vin" } }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["check_config"]).to include("check_kind" => "equals", "compare_to" => "expected", "expected_path" => "vin")
    end
  end
end

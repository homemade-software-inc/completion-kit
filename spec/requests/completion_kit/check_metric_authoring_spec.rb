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
      expect(Nokogiri::HTML5(response.body).css(".ck-error-list li").map(&:text))
        .to include('Check needs "Shortest allowed" and "Longest allowed" to be numbers')
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

    it "drops a hidden compare_to and expected_path left over from a kind that compares against the answer key" do
      post base_path, params: { metric: { name: "Switched to bounds", metric_type: "check",
                                          check_config: { check_kind: "numeric_bounds", target: "json_path", target_path: "score",
                                                          compare_to: "expected", expected_path: "score", min: "0.5" } } }

      config = CompletionKit::Metric.find_by(name: "Switched to bounds").check_config
      expect(config).to include("check_kind" => "numeric_bounds", "min" => 0.5)
      expect(config.keys).not_to include("compare_to", "expected_path")
    end

    it "stores an explicitly unchecked case_sensitive so a regex can be made case-insensitive" do
      post base_path, params: { metric: { name: "Loose regex", metric_type: "check",
                                          check_config: { check_kind: "regex", target: "response_text",
                                                          pattern: "ok", case_sensitive: "false" } } }

      expect(CompletionKit::Metric.find_by(name: "Loose regex").check_config["case_sensitive"]).to be(false)
    end

    it "persists a list_overlap check with its measure and threshold" do
      post base_path, params: { metric: { name: "Option codes", metric_type: "check",
                                          check_config: { check_kind: "list_overlap", target: "json_path",
                                                          target_path: "optionCodes", compare_to: "expected",
                                                          expected_path: "optionCodes", score_by: "recall", min: "0.8" } } }

      config = CompletionKit::Metric.find_by(name: "Option codes").check_config
      expect(config).to include("score_by" => "recall", "min" => 0.8, "compare_to" => "expected")
      expect(config).not_to have_key("value")
    end

    it "persists a numeric_equals check with its tolerance" do
      post base_path, params: { metric: { name: "Mileage", metric_type: "check",
                                          check_config: { check_kind: "numeric_equals", target: "json_path",
                                                          target_path: "mileage", compare_to: "expected",
                                                          expected_path: "mileage", tolerance: "2%" } } }

      config = CompletionKit::Metric.find_by(name: "Mileage").check_config
      expect(config).to include("tolerance" => "2%")
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

    it "saves a json_path_equals check whose expected value is a number" do
      metric = create(:completion_kit_metric, :check)

      patch "#{base_path}/#{metric.id}", params: { metric: { check_config: { check_kind: "json_path_equals", target: "response_text",
                                                                             json_path: "code", expected: "200" } } }

      expect(response).to redirect_to("#{base_path}/#{metric.id}")
      expect(metric.reload.check_config["expected"]).to eq(200)
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

  describe "validating edits to a check" do
    let(:list_config) { { "check_kind" => "list_overlap", "target" => "response_text", "value" => "A, B", "min" => 0.6 } }

    def reviewed_check(config)
      metric = create(:completion_kit_metric, :check, name: "Codes", check_config: config)
      create(:completion_kit_review, :check, response: create(:completion_kit_response), metric: metric,
             metric_version: CompletionKit::MetricVersion.ensure_current_for(metric))
      metric
    end

    def save_list(metric, min, name: metric.name)
      patch "#{base_path}/#{metric.id}", params: { metric: { name: name, check_config: list_config.merge("min" => min) } }
    end

    def page
      Nokogiri::HTML5(response.body)
    end

    def errors
      page.css(".ck-error-list li").map(&:text)
    end

    it "refuses an invalid change to a check with reviews instead of saving it as a draft" do
      metric = reviewed_check(list_config)

      expect { save_list(metric, "1.5", name: "Renamed") }.not_to change(CompletionKit::MetricVersion.drafts, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(errors).to include('Check needs "Lowest score that passes" to be a number between 0 and 1')
      expect(page.at_css('input[name="metric[check_config][min]"]')["value"]).to eq("1.5")
      expect(metric.reload.name).to eq("Codes")
      expect(metric.check_config["min"]).to eq(0.6)
    end

    it "saves the name and drafts the repair when a check with reviews has a bad saved config" do
      metric = reviewed_check(list_config)
      metric.update_column(:check_config, list_config.merge("min" => 1.5))

      expect { save_list(metric, "0.6", name: "Fixed codes") }.to change(CompletionKit::MetricVersion.drafts, :count).by(1)

      expect(response).to redirect_to("#{base_path}/#{metric.id}/edit")
      expect(metric.reload.name).to eq("Fixed codes")
      expect(metric.check_config["min"]).to eq(1.5)
      expect(CompletionKit::MetricVersion.drafts.find_by(metric_id: metric.id).check_config["min"]).to eq(0.6)
    end

    it "repairs a bad saved config in place when the check has no reviews" do
      metric = create(:completion_kit_metric, :check, check_config: list_config)
      metric.update_column(:check_config, list_config.merge("min" => 1.5))

      save_list(metric, "0.6", name: "Fixed codes")

      expect(response).to redirect_to("#{base_path}/#{metric.id}")
      expect(metric.reload).to have_attributes(name: "Fixed codes", valid?: true)
      expect(metric.check_config["min"]).to eq(0.6)
    end

    it "names the problem when a rename leaves a bad saved config in place" do
      metric = reviewed_check(list_config)
      metric.update_column(:check_config, list_config.merge("min" => 1.5))

      patch "#{base_path}/#{metric.id}", params: { metric: { name: "Renamed" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(errors).to include('Check needs "Lowest score that passes" to be a number between 0 and 1')
      expect(metric.reload.name).to eq("Codes")
    end

    it "shows the errors and keeps what was typed when a check with no reviews is saved with bad values" do
      metric = create(:completion_kit_metric, :check)

      patch "#{base_path}/#{metric.id}", params: { metric: { check_config: { check_kind: "numeric_equals", target: "response_text",
                                                                             value: "abc", tolerance: "lots" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(errors).to include('Check needs "Expected number" to be a number',
                                'Check needs "How far off is still right" to be a number that is not negative, or a percentage like 2%')
      expect(page.at_css('input[name="metric[check_config][value]"]')["value"]).to eq("abc")
      expect(page.at_css('input[name="metric[check_config][tolerance]"]')["value"]).to eq("lots")
      expect(metric.reload.check_config).to eq({ "check_kind" => "valid_json", "target" => "response_text" })
    end

    it "shows the error when a list threshold above 1 is saved on a check with no reviews" do
      metric = create(:completion_kit_metric, :check, check_config: list_config)

      save_list(metric, "1.5")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(errors).to include('Check needs "Lowest score that passes" to be a number between 0 and 1')
      expect(metric.reload.check_config["min"]).to eq(0.6)
    end

    it "loads a check draft into the edit form and says publishing replaces the live check" do
      metric = reviewed_check(list_config)
      save_list(metric, "0.8")

      get "#{base_path}/#{metric.id}/edit"

      expect(page.at_css('input[name="metric[check_config][min]"]')["value"]).to eq("0.8")
      expect(page.at_css(".ck-suggestion-banner .ck-meta-copy").text.squish)
        .to eq("The form below shows your unpublished draft. Publish to replace the live check for future runs, or keep editing.")
    end

    it "refuses to publish a check version that is not valid and leaves the live metric alone" do
      metric = reviewed_check(list_config)
      draft = CompletionKit::MetricVersion.create!(metric: metric, metric_type: "check", check_config: list_config.merge("min" => 1.5),
                                                   state: "draft", source: "edit", current: false)

      post "#{base_path}/#{metric.id}/publish_draft", params: { draft_id: draft.id }

      expect(response).to redirect_to("#{base_path}/#{metric.id}")
      expect(flash[:alert]).to eq("#{draft.version_label} was not published. Check needs \"Lowest score that passes\" to be a number between 0 and 1.")
      expect(metric.reload.check_config["min"]).to eq(0.6)
      expect(draft.reload).to be_draft
    end
  end

  describe "resaving an in-use check through the edit form" do
    let(:token) { "edit-form-token" }

    before { CompletionKit.config.api_token = token }
    after { CompletionKit.instance_variable_set(:@config, nil) }

    def review!(metric)
      create(:completion_kit_review, :check, response: create(:completion_kit_response), metric: metric,
             metric_version: CompletionKit::MetricVersion.ensure_current_for(metric))
      metric
    end

    def rest_check(name, config)
      post "/completion_kit/api/v1/metrics", params: { name: name, metric_type: "check", check_config: config }.to_json,
                                             headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
      expect(response).to have_http_status(:created), response.body
      CompletionKit::Metric.find(JSON.parse(response.body)["id"])
    end

    def resubmit_edit_form(metric, overrides)
      get "#{base_path}/#{metric.id}/edit"
      form = Nokogiri::HTML5(response.body).css("form").find { |candidate| candidate.at_css('input[name="_method"][value="patch"]') }
      fields = form.css("input, textarea").filter_map do |field|
        next if field["name"].blank?
        next if %w[checkbox radio].include?(field["type"]) && !field.key?("checked")

        [field["name"], overrides.fetch(field["name"]) { field.name == "textarea" ? field.text : field["value"].to_s }]
      end
      patch "#{base_path}/#{metric.id}", params: Rack::Utils.parse_nested_query(URI.encode_www_form(fields))
    end

    def expect_rename_without_draft(metric)
      original = metric.check_config

      expect { resubmit_edit_form(metric, "metric[name]" => "#{metric.name} renamed") }
        .not_to change(CompletionKit::MetricVersion.drafts, :count)

      expect(response).to redirect_to("#{base_path}/#{metric.id}")
      expect(metric.reload.name).to end_with("renamed")
      expect(metric.check_config).to eq(original)
    end

    it "creates no draft for contains, regex and REST list checks when only the name changes" do
      expect_rename_without_draft(review!(create(:completion_kit_metric, :check,
        check_config: { "check_kind" => "contains", "target" => "response_text", "value" => "TOKEN" })))
      expect_rename_without_draft(review!(create(:completion_kit_metric, :check,
        check_config: { "check_kind" => "regex", "target" => "response_text", "pattern" => "\\d{3}" })))
      expect_rename_without_draft(review!(rest_check("Codes", { check_kind: "list_overlap", target: "json_path",
                                                                target_path: "codes", value: %w[A B], min: 0.5 })))
    end

    it "creates no draft for REST checks whose values the form writes back as text" do
      expect_rename_without_draft(review!(rest_check("Price", { check_kind: "numeric_equals", target: "response_text",
                                                                value: 82_000, tolerance: 500 })))
      expect_rename_without_draft(review!(rest_check("Status", { check_kind: "json_path_equals", target: "response_text",
                                                                 json_path: "code", expected: "200" })))
      expect_rename_without_draft(review!(rest_check("Loose", { check_kind: "regex", target: "response_text",
                                                                pattern: "ok", case_sensitive: "false" })))
    end

    it "still drafts a real change made through the form" do
      metric = review!(create(:completion_kit_metric, :check,
        check_config: { "check_kind" => "contains", "target" => "response_text", "value" => "TOKEN" }))

      expect { resubmit_edit_form(metric, "metric[check_config][value]" => "OTHER") }
        .to change(CompletionKit::MetricVersion.drafts, :count).by(1)

      expect(CompletionKit::MetricVersion.drafts.find_by(metric_id: metric.id).check_config).to include("value" => "OTHER")
    end

    it "drafts an answer key changed between text and the number it spells" do
      text = review!(rest_check("Status text", { check_kind: "json_path_equals", target: "response_text",
                                                 json_path: "code", expected: "200" }))
      number = review!(create(:completion_kit_metric, :check,
        check_config: { "check_kind" => "json_path_equals", "target" => "response_text", "json_path" => "code", "expected" => 200 }))

      expect { resubmit_edit_form(text, "metric[check_config][expected]" => "200") }
        .to change(CompletionKit::MetricVersion.drafts, :count).by(1)
      expect(response).to redirect_to("#{base_path}/#{text.id}/edit")
      expect { resubmit_edit_form(number, "metric[check_config][expected]" => '"200"') }
        .to change(CompletionKit::MetricVersion.drafts, :count).by(1)

      expect(CompletionKit::MetricVersion.drafts.find_by(metric_id: text.id).check_config["expected"]).to eq(200)
      expect(CompletionKit::MetricVersion.drafts.find_by(metric_id: number.id).check_config["expected"]).to eq("200")
      expect(text.reload.check_config["expected"]).to eq("200")
      expect(number.reload.check_config["expected"]).to eq(200)
    end

    it "shows a REST answer key that spells a number in quotes, so saving the form unchanged keeps it as text" do
      metric = review!(rest_check("Status", { check_kind: "json_path_equals", target: "response_text",
                                              json_path: "code", expected: "200" }))

      get "#{base_path}/#{metric.id}/edit"
      page = Nokogiri::HTML5(response.body)
      expect(page.at_css('input[name="metric[check_config][expected]"]')["value"]).to eq('"200"')
      expect(page.at_css('[data-ck-check-field="expected"] .ck-hint').text).to include('in quotes, like "200", to match it as text')

      expect { resubmit_edit_form(metric, {}) }.not_to change(CompletionKit::MetricVersion.drafts, :count)
      expect(response).to redirect_to("#{base_path}/#{metric.id}")
      expect(metric.reload.check_config["expected"]).to eq("200")
    end

    it "writes a list value into the form as JSON and leaves an unticked string flag unticked" do
      list = rest_check("Codes", { check_kind: "list_overlap", target: "response_text", value: ["A", "B \"quoted\""] })
      loose = rest_check("Loose", { check_kind: "regex", target: "response_text", pattern: "ok", case_sensitive: "false" })

      get "#{base_path}/#{list.id}/edit"
      expect(Nokogiri::HTML5(response.body).at_css('input[name="metric[check_config][value]"]')["value"]).to eq('["A","B \"quoted\""]')

      get "#{base_path}/#{loose.id}/edit"
      expect(Nokogiri::HTML5(response.body).at_css('input[type=checkbox][name="metric[check_config][case_sensitive]"]').key?("checked")).to be(false)
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
      expect(Nokogiri::HTML5(response.body).at_css('[data-ck-check-field="compare_to"]').text).to include("Each row's expected value")
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

    it "offers the list and number fields, and sends false for an unticked box" do
      get "#{base_path}/new"

      page = Nokogiri::HTML5(response.body)
      expect(page.at_css('[data-ck-check-field="score_by"] .ck-label').text).to eq("How to score it")
      expect(response.body).to include('name="metric[check_config][score_by]" value="recall"')
      expect(response.body).to include(*CompletionKit::Checks::Labels::SCORE_BY.values)
      hint = page.at_css('[data-ck-check-field="score_by"] .ck-hint').text
      expect(hint).to eq(CompletionKit::Checks::Labels.hint("score_by"))
      CompletionKit::Checks::Labels::SCORE_BY.each_value do |label|
        expect(hint.downcase).to include(label.split(":").first.downcase)
      end
      expect(page.at_css('[data-ck-check-field="tolerance"] input[name="metric[check_config][tolerance]"]')).to be_present
      expect(page.at_css('input[name="metric[check_config][min]"]')["step"]).to eq("any")
      %w[min max value].each { |key| expect(page.at_css("[data-ck-check-label=#{key}]")).to be_present }
      %w[case_sensitive multiline trim].each do |flag|
        expect(page.at_css("input[type=hidden][name='metric[check_config][#{flag}]'][value=false]")).to be_present
      end
    end

    it "takes every check label, hint and field map from the labels module and the registry" do
      get "#{base_path}/new"

      page = Nokogiri::HTML5(response.body)
      editor = page.at_css('[data-ck-metric-editor="check"]')
      labels = CompletionKit::Checks::Labels
      expect(JSON.parse(editor["data-ck-check-form"])).to eq(
        "fields" => CompletionKit::Checks::Registry::CONFIG_KEYS,
        "expected" => CompletionKit::Checks::Registry::EXPECTED_KEYS,
        "labels" => labels::FIELDS_BY_KIND, "defaultLabels" => labels::FIELDS,
        "hints" => labels::HINTS_BY_KIND, "defaultHints" => labels::HINTS
      )
      editor.css("[data-ck-check-field]").each do |field|
        key = field["data-ck-check-field"]
        expect((field.at_css(".ck-label") || field.css("span").last).text.squish).to eq(labels.field(key, "contains"))
      end
      expect(editor.css("[data-ck-check-field]").map { |field| field["data-ck-check-field"] })
        .to eq(labels::FIELDS.keys - %w[check_kind target])
      expect(editor.at_css('[data-ck-check-field="compare_to"]').text).to include(labels.value("compare_to", "constant"))

      script = File.read(CompletionKit::Engine.root.join("app/assets/javascripts/completion_kit/application.js"))
      expect(script).not_to include("Shortest allowed", "Text to look for", "Leave blank", "json_path_equals")
    end

    it "sets up the check fields again when Turbo renders a failed save, not only on a full page load" do
      script = File.read(CompletionKit::Engine.root.join("app/assets/javascripts/completion_kit/application.js"))

      expect(script).to include('document.addEventListener("turbo:render", ckApplyMetricForms);')
      expect(script).to include('document.addEventListener("turbo:render", ckApplyProviderForms);')
      expect(script).to include('document.addEventListener("turbo:render", ckAutoFocusFirstError);')
    end

    it "hides the min and max row when the rule shows neither, so the row leaves no double gap" do
      css = File.read(CompletionKit::Engine.root.join("app/assets/stylesheets/completion_kit/application.css"))

      expect(css).to match(/^\.ck-field-row:not\(:has\(> \.ck-field:not\(\[hidden\]\)\)\) \{\n  display: none;\n\}/)
      get "#{base_path}/new"
      expect(Nokogiri::HTML5(response.body).css(".ck-field-row > .ck-field").map { |field| field["data-ck-check-field"] }).to eq(%w[min max])
    end

    it "renders a failed list check save with the list check's own labels and hints" do
      post base_path, params: { metric: { name: "Codes", metric_type: "check",
                                          check_config: { check_kind: "list_overlap", target: "response_text", value: "A, B", min: "5" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      page = Nokogiri::HTML5(response.body)
      expect(page.at_css('[data-ck-check-label="value"]').text).to eq("Expected list")
      expect(page.at_css('[data-ck-check-label="min"]').text).to eq("Lowest score that passes")
      expect(page.at_css('[data-ck-check-hint="min"]').text).to eq("Give a value from 0 to 1, like 0.6 for 60%. Leave blank to require a perfect score.")
    end

    it "marks each check field with an error, so focus lands on the first one after a failed save" do
      post base_path, params: { metric: { name: "Codes", metric_type: "check",
                                          check_config: { check_kind: "list_overlap", target: "response_text", value: "A, B", min: "5" } } }

      page = Nokogiri::HTML5(response.body)
      expect(page.css('form [aria-invalid="true"]').map { |node| node["name"] }).to eq(["metric[check_config][min]"])

      post base_path, params: { metric: { name: "", metric_type: "check",
                                          check_config: { check_kind: "contains", target: "json_path", target_path: "", value: "" } } }

      page = Nokogiri::HTML5(response.body)
      expect(page.css('form [aria-invalid="true"]').map { |node| node["name"] })
        .to eq(["metric[name]", "metric[check_config][target_path]", "metric[check_config][value]"])
    end

    it "marks a branded select whose choice was refused" do
      post base_path, params: { metric: { name: "Codes", metric_type: "check",
                                          check_config: { check_kind: "list_overlap", target: "telepathy", value: "A", score_by: "vibes" } } }

      page = Nokogiri::HTML5(response.body)
      invalid = page.css('form [aria-invalid="true"]')
      expect(invalid.map { |node| node["class"] }).to eq(%w[ck-select__trigger ck-select__trigger])
      expect(invalid.map { |node| node["aria-labelledby"] }).to eq(%w[metric_check_target_label metric_check_score_by_label])
      expect(page.at_css('[aria-labelledby="metric_check_kind_label"].ck-select__trigger')["aria-invalid"]).to be_nil
    end

    it "prefills a list check's measure and a number check's tolerance when editing" do
      list = create(:completion_kit_metric, :check,
        check_config: { "check_kind" => "list_overlap", "target" => "response_text", "value" => "A, B", "score_by" => "f1", "min" => 0.5 })
      number = create(:completion_kit_metric, :check,
        check_config: { "check_kind" => "numeric_equals", "target" => "response_text", "value" => 82_000, "tolerance" => "2%" })

      get "#{base_path}/#{list.id}/edit"
      expect(response.body).to include('name="metric[check_config][score_by]" value="f1"')
      expect(Nokogiri::HTML5(response.body).at_css('input[name="metric[check_config][min]"]')["value"]).to eq("0.5")

      get "#{base_path}/#{number.id}/edit"
      expect(Nokogiri::HTML5(response.body).at_css('input[name="metric[check_config][tolerance]"]')["value"]).to eq("2%")
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

    it "shows a JSON field expected to be false, while hiding an unticked flag" do
      metric = create(:completion_kit_metric, :check,
        check_config: { "check_kind" => "json_path_equals", "target" => "response_text",
                        "json_path" => "recalled", "expected" => false })
      metric.update_column(:check_config, metric.check_config.merge("case_sensitive" => false))

      get "#{base_path}/#{metric.id}"

      spec = Nokogiri::HTML5(response.body).at_css(".ck-check-spec")
      expect(spec.css(".ck-check-spec__term").map(&:text)).to include("Expected value")
      expect(spec.css(".ck-check-spec__code").map(&:text)).to include("false")
      expect(spec.text).not_to include("Case sensitive")
    end

    it "lists a check's fields in the order the form lays them out, with a ticked box as Yes" do
      metric = create(:completion_kit_metric, :check,
        check_config: { "check_kind" => "contains", "target" => "json_path", "trim" => true,
                        "case_sensitive" => true, "value" => "TOKEN", "target_path" => "data.field" })

      get "#{base_path}/#{metric.id}"

      spec = Nokogiri::HTML5(response.body).at_css(".ck-check-spec")
      expect(spec.css(".ck-check-spec__term").map(&:text))
        .to eq(["Rule", "What to check", "Path into the JSON", "Text to look for", "Case sensitive", "Trim whitespace"])
      flags = spec.css(".ck-check-spec__row").select { |row| row.at_css(".ck-check-spec__term").text.in?(["Case sensitive", "Trim whitespace"]) }
      expect(flags.map { |row| row.at_css(".ck-check-spec__val").text.squish }).to eq(%w[Yes Yes])
      expect(flags.flat_map { |row| row.css(".ck-check-spec__code") }).to be_empty
      expect(spec.css(".ck-check-spec__code").map(&:text)).to eq(["data.field", "TOKEN"])
    end

    it "shows a list value on the metric page as the JSON the form takes" do
      metric = create(:completion_kit_metric, :check,
        check_config: { "check_kind" => "list_overlap", "target" => "response_text", "value" => %w[A B] })

      get "#{base_path}/#{metric.id}"

      expect(Nokogiri::HTML5(response.body).at_css(".ck-check-spec .ck-check-spec__code").text).to eq('["A","B"]')
    end

    it "shows a list check's measure and threshold in the words the form uses" do
      metric = create(:completion_kit_metric, :check,
        check_config: { "check_kind" => "list_overlap", "target" => "response_text",
                        "value" => "A, B", "score_by" => "f1", "min" => 0.5 })

      get "#{base_path}/#{metric.id}"

      spec = Nokogiri::HTML5(response.body).at_css(".ck-check-spec")
      expect(spec.css(".ck-check-spec__term").map(&:text)).to include("Expected list", "How to score it", "Lowest score that passes")
      expect(spec.text).to include("Balance: coverage and accuracy weighed equally")
      expect(spec.text).not_to include("f1")
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

    def create_check(name, config)
      post "/completion_kit/api/v1/metrics", params: { name: name, metric_type: "check", check_config: config }.to_json, headers: headers
      expect(response).to have_http_status(:created), response.body
      JSON.parse(response.body)["check_config"]
    end

    it "creates a list_overlap check from a JSON list, keeping score_by and min" do
      config = create_check("Codes", { check_kind: "list_overlap", target: "json_path", target_path: "$.optionCodes",
                                       value: %w[A B C], score_by: "f1", min: 0.5 })

      expect(config).to include("value" => %w[A B C], "score_by" => "f1", "min" => 0.5, "target_path" => "$.optionCodes")
    end

    it "creates a list_overlap check graded against each row's answer key" do
      config = create_check("Codes vs key", { check_kind: "list_overlap", target: "json_path", target_path: "optionCodes",
                                              compare_to: "expected", expected_path: "optionCodes", score_by: "jaccard" })

      expect(config).to include("compare_to" => "expected", "expected_path" => "optionCodes", "score_by" => "jaccard")
    end

    it "creates a numeric_bounds check" do
      config = create_check("Confidence", { check_kind: "numeric_bounds", target: "json_path", target_path: "vin.confidence", min: 0.8, max: 1 })

      expect(config).to include("check_kind" => "numeric_bounds", "min" => 0.8, "max" => 1)
    end

    it "creates a numeric_equals check, keeping a percentage or a plain number tolerance" do
      expect(create_check("Price", { check_kind: "numeric_equals", target: "response_text", value: "24995", tolerance: "2%" }))
        .to include("value" => "24995", "tolerance" => "2%")
      expect(create_check("Mileage", { check_kind: "numeric_equals", target: "json_path", target_path: "mileage",
                                       compare_to: "expected", expected_path: "mileage", tolerance: 500 }))
        .to include("tolerance" => 500, "compare_to" => "expected")
    end

    it "creates a json_path_equals check graded against each row's answer key" do
      config = create_check("VIN field", { check_kind: "json_path_equals", target: "response_text", json_path: "vin",
                                           compare_to: "expected", expected_path: "vin" })

      expect(config).to include("check_kind" => "json_path_equals", "compare_to" => "expected", "expected_path" => "vin")
    end

    it "updates a list_overlap value to a JSON list" do
      metric = create(:completion_kit_metric, :check, check_config: { "check_kind" => "list_overlap", "target" => "response_text", "value" => "A" })

      patch "/completion_kit/api/v1/metrics/#{metric.id}", params: { check_config: { check_kind: "list_overlap", target: "response_text", value: %w[A B] } }.to_json,
                                                          headers: headers

      expect(response).to have_http_status(:ok)
      expect(metric.reload.check_config["value"]).to eq(%w[A B])
    end

    it "creates a comparison check graded against each row's expected value" do
      post "/completion_kit/api/v1/metrics",
           params: { name: "VIN match", metric_type: "check",
                     check_config: { check_kind: "equals", target: "json_path", target_path: "vin", compare_to: "expected", expected_path: "vin" } }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["check_config"]).to include("check_kind" => "equals", "compare_to" => "expected", "expected_path" => "vin")
    end

    it "reads a target_path sent with no target as a path into the response JSON (issue #170)" do
      config = create_check("Confidence", { check_kind: "numeric_bounds", target_path: "$.vin.confidence", min: 0.8 })

      expect(config).to include("target" => "json_path", "target_path" => "$.vin.confidence")
    end

    it "refuses a target_path when the target says to check something else" do
      post "/completion_kit/api/v1/metrics",
           params: { name: "Confidence", metric_type: "check",
                     check_config: { check_kind: "numeric_bounds", target: "input_data", target_path: "$.vin.confidence", min: 0.8 } }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["details"]["check_config"])
        .to eq(['needs "What to check" to be "A value from the response JSON" when "Path into the JSON" is filled in'])
    end

    it "refuses a list value on a rule that compares one value, as 0.28.46 did" do
      post "/completion_kit/api/v1/metrics",
           params: { name: "Contains list", metric_type: "check", check_config: { check_kind: "contains", target: "response_text", value: %w[foo bar] } }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["details"]["check_config"]).to eq(['needs "Text to look for" to be a single value, since only list_overlap takes a list'])
      expect(CompletionKit::Metric.where(name: "Contains list")).to be_empty
    end

    it "refuses a list value when updating a rule that compares one value" do
      metric = create(:completion_kit_metric, :check, check_config: { "check_kind" => "equals", "target" => "response_text", "value" => "foo" })

      patch "/completion_kit/api/v1/metrics/#{metric.id}", params: { check_config: { check_kind: "equals", target: "response_text", value: %w[foo] } }.to_json,
                                                          headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(metric.reload.check_config["value"]).to eq("foo")
    end
  end
end

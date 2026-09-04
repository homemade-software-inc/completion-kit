require "rails_helper"

RSpec.describe CompletionKit::Metric, type: :model do
  describe "destroy cascade" do
    it "destroys metric_group memberships and nullifies the metric link on reviews" do
      metric = create(:completion_kit_metric)
      group = create(:completion_kit_metric_group)
      create(:completion_kit_metric_group_membership, metric_group: group, metric: metric)
      response = create(:completion_kit_response, run: create(:completion_kit_run, prompt: create(:completion_kit_prompt, template: "Static prompt without variables")))
      review = create(:completion_kit_review, response: response, metric: metric)

      expect { metric.destroy! }
        .to change(CompletionKit::MetricGroupMembership, :count).by(-1)
        .and change(CompletionKit::Review, :count).by(0)

      expect(review.reload.metric_id).to be_nil
    end

    it "destroys run_metrics join rows so a metric used in a run can be deleted" do
      metric = create(:completion_kit_metric)
      run = create(:completion_kit_run, prompt: create(:completion_kit_prompt, template: "Static prompt without variables"))
      CompletionKit::RunMetric.create!(run: run, metric: metric)

      expect { metric.destroy! }.to change(CompletionKit::RunMetric, :count).by(-1)
      expect(CompletionKit::RunMetric.where(metric_id: metric.id)).not_to exist
    end
  end

  it "fills in default rubric bands on a new metric" do
    metric = described_class.create!(name: "Default metric", instruction: "Rate quality.")

    expect(metric.rubric_bands.length).to eq(5)
    expect(metric.rubric_bands.first).to include("stars" => 5)
    expect(metric.rubric_bands.last).to include("stars" => 1)
  end

  it "rejects an llm_judge metric with a blank instruction" do
    metric = build(:completion_kit_metric, instruction: "")

    expect(metric).not_to be_valid
    expect(metric.errors[:instruction].join).to include("needs a rubric to score against")
  end

  it "allows a check metric with no instruction" do
    expect(build(:completion_kit_metric, :check)).to be_valid
  end

  describe "metric_type" do
    it "defaults a new metric to llm_judge" do
      expect(described_class.new.metric_type).to eq("llm_judge")
      expect(described_class.new).to be_llm_judge
      expect(described_class.new).not_to be_check
    end

    it "recognizes a check metric" do
      metric = build(:completion_kit_metric, :check)
      expect(metric).to be_check
      expect(metric).not_to be_llm_judge
    end

    it "rejects an unknown metric_type" do
      metric = build(:completion_kit_metric, metric_type: "bogus")
      expect(metric).not_to be_valid
      expect(metric.errors[:metric_type]).to be_present
    end
  end

  describe "check metrics" do
    it "does not stamp phantom rubric defaults on a check" do
      metric = create(:completion_kit_metric, :check)
      expect(metric.rubric_bands).to be_nil
      expect(metric.instruction).to be_nil
    end

    it "round-trips check_config as a hash" do
      metric = create(:completion_kit_metric, :check,
                      check_config: { "check_kind" => "contains", "target" => "response_text", "value" => "ok" })
      expect(metric.reload.check_config).to eq({ "check_kind" => "contains", "target" => "response_text", "value" => "ok" })
    end

    it "is invalid when check_config is not a hash" do
      metric = build(:completion_kit_metric, :check, check_config: "nope")
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config]).to be_present
    end

    it "is invalid for an unknown check_kind" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "telepathy", "target" => "response_text" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("check_kind")
    end

    it "is invalid when a required per-kind key is missing" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "contains", "target" => "response_text" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("value")
    end

    it "is invalid for an unknown target" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "valid_json", "target" => "telepathy" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("target")
    end

    it "requires target_path when target is json_path" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "valid_json", "target" => "json_path" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("target_path")
    end

    it "is invalid when a regex pattern will not compile" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "regex", "target" => "response_text", "pattern" => "(" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("regular expression")
    end

    it "requires at least one bound for length_bounds" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "length_bounds", "target" => "response_text" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("min or max")
    end

    it "rejects length_bounds where min exceeds max" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "length_bounds", "target" => "response_text", "min" => 9, "max" => 2 })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("less than or equal")
    end

    it "accepts a valid length_bounds with both bounds" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "length_bounds", "target" => "response_text", "min" => 2, "max" => 9 })
      expect(metric).to be_valid
    end

    it "treats a blank bound as absent rather than as a zero that can never fail" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "length_bounds", "target" => "response_text", "min" => "", "max" => "" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("min or max")
    end

    it "rejects a bound that is not a number" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "length_bounds", "target" => "response_text", "min" => "abc" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("must be numbers")

      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "length_bounds", "target" => "response_text", "max" => "abc" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("must be numbers")
    end

    it "applies the same bound rules to numeric_bounds" do
      expect(build(:completion_kit_metric, :check, check_config: { "check_kind" => "numeric_bounds", "target" => "response_text" })).not_to be_valid
      expect(build(:completion_kit_metric, :check, check_config: { "check_kind" => "numeric_bounds", "target" => "response_text", "min" => 0.8 })).to be_valid
      expect(build(:completion_kit_metric, :check, check_config: { "check_kind" => "numeric_bounds", "target" => "response_text", "min" => 9, "max" => 2 })).not_to be_valid
    end

    it "accepts list_overlap with a known measure and a threshold in range" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "list_overlap", "target" => "response_text", "value" => "a,b", "score_by" => "f1", "min" => 0.8 })
      expect(metric).to be_valid
    end

    it "accepts list_overlap with no measure and no threshold" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "list_overlap", "target" => "response_text", "value" => "a,b" })
      expect(metric).to be_valid
    end

    it "rejects an unknown list_overlap measure" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "list_overlap", "target" => "response_text", "value" => "a", "score_by" => "vibes" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("score_by must be one of")
    end

    it "rejects a list_overlap threshold outside zero to one" do
      %w[abc -0.5 1.5].each do |threshold|
        metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "list_overlap", "target" => "response_text", "value" => "a", "min" => threshold })
        expect(metric).not_to be_valid
        expect(metric.errors[:check_config].join).to include("between 0 and 1")
      end
    end

    it "does not require value on list_overlap when it grades against the row's expected value" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "list_overlap", "target" => "response_text", "compare_to" => "expected" })
      expect(metric).to be_valid
    end

    it "accepts numeric_equals with a numeric value and tolerance" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "numeric_equals", "target" => "response_text", "value" => "2020", "tolerance" => 1 })
      expect(metric).to be_valid
    end

    it "accepts numeric_equals with no tolerance at all" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "numeric_equals", "target" => "response_text", "value" => 2020 })
      expect(metric).to be_valid
    end

    it "rejects a numeric_equals value that is not a number" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "numeric_equals", "target" => "response_text", "value" => "twenty" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("value must be a number")
    end

    it "skips the numeric_equals value rule when the operand comes from the row" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "numeric_equals", "target" => "response_text", "compare_to" => "expected" })
      expect(metric).to be_valid
    end

    it "rejects an unusable numeric_equals tolerance" do
      %w[abc -1].each do |tolerance|
        metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "numeric_equals", "target" => "response_text", "value" => 1, "tolerance" => tolerance })
        expect(metric).not_to be_valid
        expect(metric.errors[:check_config].join).to include("tolerance must be a number")
      end
    end

    it "accepts a percentage tolerance" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "numeric_equals", "target" => "response_text", "value" => 2020, "tolerance" => "2%" })
      expect(metric).to be_valid
    end

    it "rejects a percentage tolerance that is not a number" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "numeric_equals", "target" => "response_text", "value" => 1, "tolerance" => "loads%" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("or a percentage like 2%")
    end

    it "lets json_path_equals grade against the row's expected value without a constant" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "json_path_equals", "target" => "response_text", "json_path" => "vin", "compare_to" => "expected", "expected_path" => "vin" })
      expect(metric).to be_valid
    end

    it "accepts json_path_equals only when expected is present even if falsey" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "json_path_equals", "target" => "response_text", "json_path" => "ok", "expected" => false })
      expect(metric).to be_valid
    end

    it "is invalid when json_path_equals omits expected entirely" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "json_path_equals", "target" => "response_text", "json_path" => "ok" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("expected")
    end

    it "does not require value when a comparison check grades against the row's expected value" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "equals", "target" => "response_text", "compare_to" => "expected" })
      expect(metric).to be_valid
    end

    it "still requires value for a comparison check that compares to a constant" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "equals", "target" => "response_text", "compare_to" => "constant" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("value")
    end

    it "is invalid when compare_to is neither constant nor expected" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "equals", "target" => "response_text", "compare_to" => "guess", "value" => "x" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("compare_to must be constant or expected")
    end

    it "rejects compare_to expected on a check kind that has no value operand" do
      metric = build(:completion_kit_metric, :check, check_config: { "check_kind" => "valid_json", "target" => "response_text", "compare_to" => "expected" })
      expect(metric).not_to be_valid
      expect(metric.errors[:check_config].join).to include("only applies to")
    end
  end

  describe "#in_use?" do
    it "is false until a run references the metric" do
      expect(create(:completion_kit_metric)).not_to be_in_use
    end

    it "is true once a run references the metric" do
      metric = create(:completion_kit_metric)
      run = create(:completion_kit_run)
      run.run_metrics.create!(metric: metric, position: 1)
      expect(metric.reload).to be_in_use
    end
  end

  describe "metric_type immutability" do
    it "rejects changing metric_type once the metric is in use" do
      metric = create(:completion_kit_metric, :check)
      run = create(:completion_kit_run)
      run.run_metrics.create!(metric: metric, position: 1)

      metric.metric_type = "llm_judge"
      expect(metric.save).to be(false)
      expect(metric.errors[:metric_type]).to be_present
    end

    it "allows non-type edits on an in-use metric" do
      metric = create(:completion_kit_metric, :check)
      run = create(:completion_kit_run)
      run.run_metrics.create!(metric: metric, position: 1)

      metric.name = "Renamed Check"
      expect(metric.save).to be(true)
    end

    it "allows changing metric_type while the metric is still unused" do
      metric = create(:completion_kit_metric, :check)

      metric.metric_type = "llm_judge"
      metric.instruction = "Rate quality."
      expect(metric.save).to be(true)
    end

    it "stays type-locked after the referencing run is deleted because a version snapshot survives" do
      metric = create(:completion_kit_metric, :check)
      run = create(:completion_kit_run)
      run.run_metrics.create!(metric: metric, position: 1)
      CompletionKit::MetricVersion.ensure_current_for(metric)
      run.destroy!

      expect(metric.reload).to be_in_use
      metric.metric_type = "llm_judge"
      expect(metric.save).to be(false)
    end
  end

  it "generates rubric text from star bands" do
    metric = described_class.create!(name: "Test metric", instruction: "Rate quality.")

    expect(metric.display_rubric_text).to include("5 stars:")
    expect(metric.display_rubric_text).to include("1 star:")
  end

  it "normalizes rubric bands preserving only valid star entries" do
    metric = build(
      :completion_kit_metric,
      rubric_bands: [
        "junk",
        { stars: 99, description: "Ignore" },
        { stars: 5, description: "Great" },
        { stars: 3, description: "OK" }
      ]
    )

    metric.valid?

    expect(metric.rubric_bands.length).to eq(5)
    expect(metric.rubric_bands.find { |b| b["stars"] == 5 }["description"]).to eq("Great")
    expect(metric.rubric_bands.find { |b| b["stars"] == 3 }["description"]).to eq("OK")
  end

  it "normalizes rubric bands from indexed hash params (form submission)" do
    metric = build(
      :completion_kit_metric,
      rubric_bands: {"0" => {"stars" => "5", "description" => "Great"}, "1" => {"stars" => "3", "description" => "OK"}}
    )

    metric.valid?

    expect(metric.rubric_bands.length).to eq(5)
    expect(metric.rubric_bands.find { |b| b["stars"] == 5 }["description"]).to eq("Great")
    expect(metric.rubric_bands.find { |b| b["stars"] == 3 }["description"]).to eq("OK")
  end

  it "generates a unique key from name" do
    metric = described_class.create!(name: "Hallucination Detection", instruction: "Rate quality.")

    expect(metric.key).to eq("hallucination-detection")
  end
end

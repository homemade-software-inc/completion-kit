require "rails_helper"

RSpec.describe CompletionKit::CheckReviewJob, type: :job do
  let(:metric) do
    create(:completion_kit_metric, :check,
           check_config: { "check_kind" => "contains", "target" => "response_text", "value" => "ok" })
  end
  let(:run) { create(:completion_kit_run) }
  let(:response) { create(:completion_kit_response, run: run, response_text: "all ok here") }

  before do
    CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
  end

  it "writes one succeeded review carrying passed, nil ai_score, and the detail in ai_feedback" do
    described_class.perform_now(response.id, metric.id, run.id)

    review = response.reviews.find_by(metric_id: metric.id)
    expect(response.reviews.count).to eq(1)
    expect(review.status).to eq("succeeded")
    expect(review.passed).to be(true)
    expect(review.ai_score).to be_nil
    expect(review.ai_feedback).to eq("contains \"ok\"")
    expect(review.metric_name).to eq(metric.name)
    expect(review.metric_version_id).to eq(CompletionKit::MetricVersion.ensure_current_for(metric).id)
  end

  it "records passed:false with a resolution detail when the target cannot be resolved" do
    metric.update!(check_config: { "check_kind" => "not_contains", "target" => "json_path", "target_path" => "a", "value" => "x" })
    response.update!(response_text: "not json at all")

    described_class.perform_now(response.id, metric.id, run.id)

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.status).to eq("succeeded")
    expect(review.passed).to be(false)
    expect(review.ai_feedback).to eq("could not resolve target")
  end

  context "with a comparison check graded against the row's answer key (compare_to: expected)" do
    let(:metric) do
      create(:completion_kit_metric, :check,
             check_config: { "check_kind" => "equals", "target" => "json_path", "target_path" => "vin",
                             "compare_to" => "expected", "expected_path" => "vin" })
    end
    let(:response) do
      create(:completion_kit_response, run: run,
             response_text: '{"vin":"5YFBURHE0KP891234"}', expected_output: '{"vin":"5YFBURHE0KP891234"}')
    end

    it "passes when the output field matches this row's expected value" do
      described_class.perform_now(response.id, metric.id, run.id)

      review = response.reviews.find_by(metric_id: metric.id)
      expect(review.passed).to be(true)
    end

    it "fails when the output field does not match this row's expected value" do
      response.update!(response_text: '{"vin":"WRONGVIN000000000"}')

      described_class.perform_now(response.id, metric.id, run.id)

      review = response.reviews.find_by(metric_id: metric.id)
      expect(review.passed).to be(false)
    end

    it "grades a contains check against the row's expected value too" do
      metric.update!(check_config: { "check_kind" => "contains", "target" => "response_text", "compare_to" => "expected" })
      response.update!(response_text: "the VIN is 5YFBURHE0KP891234, extracted", expected_output: "5YFBURHE0KP891234")

      described_class.perform_now(response.id, metric.id, run.id)

      expect(response.reviews.find_by(metric_id: metric.id).passed).to be(true)
    end

    it "fails with a clear detail when the row has no expected value, never raising" do
      response.update!(expected_output: nil)

      expect { described_class.perform_now(response.id, metric.id, run.id) }.not_to raise_error

      review = response.reviews.find_by(metric_id: metric.id)
      expect(review.status).to eq("succeeded")
      expect(review.passed).to be(false)
      expect(review.ai_feedback).to eq("no expected value for this row")
    end
  end

  context "with a JSON field graded against the row's answer key (issue #168)" do
    let(:metric) do
      create(:completion_kit_metric, :check,
             check_config: { "check_kind" => "json_path_equals", "json_path" => "trim",
                             "compare_to" => "expected", "expected_path" => "trim" })
    end
    let(:response) do
      create(:completion_kit_response, run: run,
             response_text: '{"vin":"X1","trim":"XSE"}', expected_output: '{"vin":"X1","trim":"XSE"}')
    end

    it "grades one branch of a multi-field record against the matching branch of the answer key" do
      described_class.perform_now(response.id, metric.id, run.id)

      review = response.reviews.find_by(metric_id: metric.id)
      expect(review.passed).to be(true)
      expect(review.ai_feedback).to eq("trim == \"XSE\"")
    end

    it "fails when that one field is wrong even though the rest of the record matches" do
      response.update!(response_text: '{"vin":"X1","trim":"LE"}')

      described_class.perform_now(response.id, metric.id, run.id)

      expect(response.reviews.find_by(metric_id: metric.id).passed).to be(false)
    end

    it "keeps the answer key's type, so a number matches a number" do
      metric.update!(check_config: { "check_kind" => "json_path_equals", "json_path" => "year",
                                     "compare_to" => "expected", "expected_path" => "year" })
      response.update!(response_text: '{"year":2019}', expected_output: '{"year":2019}')

      described_class.perform_now(response.id, metric.id, run.id)

      expect(response.reviews.find_by(metric_id: metric.id).passed).to be(true)
    end

    it "fills expected rather than value, leaving the constant form untouched" do
      metric.update!(check_config: { "check_kind" => "json_path_equals", "json_path" => "trim", "expected" => "XSE" })

      described_class.perform_now(response.id, metric.id, run.id)

      expect(response.reviews.find_by(metric_id: metric.id).passed).to be(true)
    end
  end

  context "with a set-overlap check over a list-valued field (issue #169)" do
    let(:metric) do
      create(:completion_kit_metric, :check,
             check_config: { "check_kind" => "set_overlap", "target" => "json_path", "target_path" => "optionCodes",
                             "compare_to" => "expected", "expected_path" => "optionCodes",
                             "measure" => "recall", "min" => 0.8 })
    end
    let(:response) do
      create(:completion_kit_response, run: run,
             response_text: '{"optionCodes":["A","B","C","D"]}',
             expected_output: '{"optionCodes":["A","B","C","D","E","F"]}')
    end

    it "stores the fraction on the review, so the tuned number gets run history" do
      described_class.perform_now(response.id, metric.id, run.id)

      review = response.reviews.find_by(metric_id: metric.id)
      expect(review.score_fraction.to_f).to eq(0.6667)
      expect(review.ai_feedback).to eq("recall 0.6667 (4 of 6 expected, 4 returned)")
      expect(review.passed).to be(false)
      expect(review.ai_score).to be_nil
    end

    it "separates a partial answer from a total miss, which every other kind reports the same" do
      response.update!(response_text: '{"optionCodes":[]}')
      described_class.perform_now(response.id, metric.id, run.id)

      expect(response.reviews.find_by(metric_id: metric.id).score_fraction.to_f).to eq(0.0)
    end

    it "passes once the fraction clears the threshold" do
      response.update!(response_text: '{"optionCodes":["A","B","C","D","E"]}')
      described_class.perform_now(response.id, metric.id, run.id)

      review = response.reviews.find_by(metric_id: metric.id)
      expect(review.score_fraction.to_f).to eq(0.8333)
      expect(review.passed).to be(true)
    end

    it "does not let a degrading answer key push the run's average up" do
      rows = [['{"optionCodes":["A","B"]}', '{"optionCodes":["A","B","C","D"]}'],
              ['{"optionCodes":["A"]}', '{"optionCodes":["A","B","C","D"]}'],
              ['{"optionCodes":["A"]}', nil]]
      rows.each_with_index do |(text, expected), index|
        row = create(:completion_kit_response, run: run, status: "succeeded", row_index: index + 1,
                     response_text: text, expected_output: expected)
        described_class.perform_now(row.id, metric.id, run.id)
      end
      response.destroy!

      summary = CompletionKit::Run.find(run.id).metric_averages.first
      expect(summary[:count]).to eq(3)
      expect(summary[:avg_fraction]).to eq(0.25)
      expect(CompletionKit::Run.preload_summaries([CompletionKit::Run.find(run.id)]).first.metric_averages)
        .to eq([summary])
    end

    it "records a zero rather than no score when the row cannot be graded, so the average cannot drift up" do
      response.update!(expected_output: nil)

      described_class.perform_now(response.id, metric.id, run.id)

      review = response.reviews.find_by(metric_id: metric.id)
      expect(review.ai_feedback).to eq("no expected value for this row")
      expect(review.passed).to be(false)
      expect(review.score_fraction.to_f).to eq(0.0)
    end

    it "records a zero when the target cannot be resolved either" do
      response.update!(response_text: "not json at all")

      described_class.perform_now(response.id, metric.id, run.id)

      review = response.reviews.find_by(metric_id: metric.id)
      expect(review.ai_feedback).to eq("could not resolve target")
      expect(review.score_fraction.to_f).to eq(0.0)
    end

    it "reads the list as a list rather than as the stringified array a text target would give" do
      response.update!(response_text: '{"optionCodes":["A",null,"B"]}')

      expect { described_class.perform_now(response.id, metric.id, run.id) }.not_to raise_error
      expect(response.reviews.find_by(metric_id: metric.id).score_fraction.to_f).to eq(0.3333)
    end
  end

  context "with numeric checks over an extracted value (issue #170)" do
    it "bounds a confidence that a length check could never express" do
      metric.update!(check_config: { "check_kind" => "numeric_bounds", "target" => "json_path",
                                     "target_path" => "vin.confidence", "min" => 0.8 })
      response.update!(response_text: '{"vin":{"value":"X1","confidence":0.92}}')

      described_class.perform_now(response.id, metric.id, run.id)

      review = response.reviews.find_by(metric_id: metric.id)
      expect(review.passed).to be(true)
      expect(review.ai_feedback).to eq("0.92 is within bounds")
      expect(review.score_fraction).to be_nil
    end

    it "leaves a pass-or-fail check with no fraction, so it never enters a score average" do
      metric.update!(check_config: { "check_kind" => "numeric_bounds", "target" => "json_path",
                                     "target_path" => "nope", "min" => 0.8 })

      described_class.perform_now(response.id, metric.id, run.id)

      review = response.reviews.find_by(metric_id: metric.id)
      expect(review.ai_feedback).to eq("could not resolve target")
      expect(review.score_fraction).to be_nil
    end

    it "fails a confidence below the floor" do
      metric.update!(check_config: { "check_kind" => "numeric_bounds", "target" => "json_path",
                                     "target_path" => "vin.confidence", "min" => 0.8 })
      response.update!(response_text: '{"vin":{"value":"X1","confidence":0.41}}')

      described_class.perform_now(response.id, metric.id, run.id)

      expect(response.reviews.find_by(metric_id: metric.id).passed).to be(false)
    end

    it "accepts a figure within tolerance of the row's expected figure" do
      metric.update!(check_config: { "check_kind" => "numeric_equals", "target" => "json_path",
                                     "target_path" => "mileage", "compare_to" => "expected",
                                     "expected_path" => "mileage", "tolerance" => 0.02,
                                     "tolerance_mode" => "relative" })
      response.update!(response_text: '{"mileage":"82,000"}', expected_output: '{"mileage":82500}')

      described_class.perform_now(response.id, metric.id, run.id)

      review = response.reviews.find_by(metric_id: metric.id)
      expect(review.passed).to be(true)
      expect(review.ai_feedback).to eq("82000 vs 82500, within 1650")
    end

    it "still fails a figure that is genuinely wrong" do
      metric.update!(check_config: { "check_kind" => "numeric_equals", "target" => "json_path",
                                     "target_path" => "year", "compare_to" => "expected",
                                     "expected_path" => "year", "tolerance" => 1 })
      response.update!(response_text: '{"year":1980}', expected_output: '{"year":2020}')

      described_class.perform_now(response.id, metric.id, run.id)

      expect(response.reviews.find_by(metric_id: metric.id).passed).to be(false)
    end
  end

  it "records a genuine internal exception as failed and still enqueues the completion check" do
    allow(CompletionKit::Checks::Registry).to receive(:fetch).and_raise(RuntimeError, "boom")
    expect(CompletionKit::RunCompletionCheckJob).to receive(:perform_later).with(run.id)

    expect { described_class.perform_now(response.id, metric.id, run.id) }.not_to raise_error

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.status).to eq("failed")
    expect(review.metric_name).to eq(metric.name)
  end

  it "reuses the existing review row instead of creating a duplicate" do
    response.reviews.create!(metric: metric, metric_name: metric.name,
                             metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
                             status: "pending")

    expect { described_class.perform_now(response.id, metric.id, run.id) }
      .not_to change { response.reviews.count }
  end

  it "tail-calls RunCompletionCheckJob after a successful check" do
    expect(CompletionKit::RunCompletionCheckJob).to receive(:perform_later).with(run.id)
    described_class.perform_now(response.id, metric.id, run.id)
  end

  it "does not raise when the response row is missing and enqueues nothing" do
    expect(CompletionKit::RunCompletionCheckJob).not_to receive(:perform_later)
    expect { described_class.perform_now(0, metric.id, run.id) }.not_to raise_error
  end

  it "falls back to (deleted metric) name when the metric is gone on failure" do
    allow(CompletionKit::Checks::Registry).to receive(:fetch).and_raise(RuntimeError, "boom")
    metric_id = metric.id
    CompletionKit::RunMetric.where(metric_id: metric_id).delete_all
    metric.destroy!

    expect { described_class.perform_now(response.id, metric_id, run.id) }.not_to raise_error

    review = response.reviews.find_by(metric_id: metric_id)
    expect(review.metric_name).to eq("(deleted metric)")
  end

  it "keeps an existing review's metric_name on failure" do
    response.reviews.create!(metric: metric, metric_name: "Locked Name",
                             metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
                             status: "pending")
    job = described_class.new
    job.instance_variable_set(:@response_id, response.id)
    job.instance_variable_set(:@metric_id, metric.id)

    job.send(:record_terminal_failure!, RuntimeError.new("boom"))

    expect(response.reviews.find_by(metric_id: metric.id).metric_name).to eq("Locked Name")
  end
end

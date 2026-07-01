require "rails_helper"
require "faraday"

RSpec.describe CompletionKit::Run, type: :model do
  before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_status_header)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_actions)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_sort_toolbar)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_clear_responses)
  end

  describe ".display_scoped" do
    it "returns all runs when no runs_display_scope is configured" do
      recent = create(:completion_kit_run)
      old = create(:completion_kit_run, created_at: 90.days.ago)
      expect(CompletionKit::Run.display_scoped).to match_array([recent, old])
    end

    it "applies the configured callable to the current relation" do
      recent = create(:completion_kit_run)
      create(:completion_kit_run, created_at: 90.days.ago)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      expect(CompletionKit::Run.display_scoped).to eq([recent])
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "preserves the receiving relation's own conditions while applying the filter" do
      keep = create(:completion_kit_run)
      create(:completion_kit_run)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      expect(CompletionKit::Run.where(id: keep.id).display_scoped).to eq([keep])
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "preserves an association scope when filtering a dataset's runs" do
      dataset = create(:completion_kit_dataset)
      mine = create(:completion_kit_run, dataset: dataset)
      create(:completion_kit_run)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      expect(dataset.runs.display_scoped).to eq([mine])
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "exposes visible_run_ids as a subquery usable by child records" do
      recent = create(:completion_kit_run)
      create(:completion_kit_run, created_at: 90.days.ago)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      expect(CompletionKit::Run.where(id: CompletionKit::Run.visible_run_ids)).to eq([recent])
    ensure
      CompletionKit.config.runs_display_scope = nil
    end
  end

  describe "#regrade!" do
    let(:run) { create(:completion_kit_run, judge_model: "gpt-4.1") }
    let(:metric) { create(:completion_kit_metric) }

    before do
      allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
      allow(CompletionKit::JudgeReviewJob).to receive(:perform_later)
      allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true)
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
    end

    it "resets each succeeded response's review back to pending and re-enqueues JudgeReviewJob for every metric x response" do
      response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: "scored")
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      review = create(:completion_kit_review, response: response_row, metric: metric, metric_name: metric.name, ai_score: 5, status: "succeeded", metric_version_id: v1.id)

      expect(run.regrade!).to be(true)

      review.reload
      expect(review.status).to eq("pending")
      expect(review.ai_score).to be_nil
      expect(review.metric_version_id).to be_nil
      expect(run.reload.status).to eq("running")
      expect(CompletionKit::JudgeReviewJob).to have_received(:perform_later).with(response_row.id, metric.id, run.id)
    end

    it "returns false and does no work when the run has no eligible succeeded responses" do
      expect(run.regrade!).to be(false)
      expect(CompletionKit::JudgeReviewJob).not_to have_received(:perform_later)
    end

    it "returns false when the run has no metrics attached" do
      bare_run = create(:completion_kit_run, judge_model: "gpt-4.1")
      create(:completion_kit_response, run: bare_run, status: "succeeded", response_text: "ok")
      expect(bare_run.regrade!).to be(false)
    end

    it "returns false when no judge_model is configured on the run" do
      judgeless_run = create(:completion_kit_run, judge_model: nil)
      CompletionKit::RunMetric.create!(run: judgeless_run, metric: metric, position: 1)
      create(:completion_kit_response, run: judgeless_run, status: "succeeded", response_text: "ok")
      expect(judgeless_run.regrade!).to be(false)
    end
  end

  describe "#stale_review_summary" do
    it "returns an empty hash when there are no reviews" do
      run = create(:completion_kit_run)
      expect(run.stale_review_summary).to eq({})
    end

    it "returns an empty hash when all reviews are stamped against the current metric_version" do
      run = create(:completion_kit_run)
      metric = create(:completion_kit_metric)
      current = CompletionKit::MetricVersion.ensure_current_for(metric)
      response = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 4, metric_version_id: current.id)
      expect(run.stale_review_summary).to eq({})
    end

    it "returns the metric, stale labels, current label, and stale count when a review's metric_version is superseded" do
      run = create(:completion_kit_run)
      metric = create(:completion_kit_metric)
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      response = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 4, metric_version_id: v1.id)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      v2.publish!
      summary = run.stale_review_summary
      expect(summary[metric.id][:metric_name]).to eq(metric.name)
      expect(summary[metric.id][:current_label]).to eq("v2")
      expect(summary[metric.id][:scored_labels]).to eq(["v1"])
      expect(summary[metric.id][:stale_count]).to eq(1)
    end

    it "skips reviews missing a metric_version stamp or a current published version" do
      run = create(:completion_kit_run)
      metric = create(:completion_kit_metric)
      response = create(:completion_kit_response, run: run)
      review = build(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 4, metric_version: nil)
      review.save(validate: false)
      expect(run.stale_review_summary).to eq({})
    end

    it "skips reviews whose metric_version_id points at a row that no longer exists" do
      run = create(:completion_kit_run)
      metric = create(:completion_kit_metric)
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      v2.publish!
      response = create(:completion_kit_response, run: run)
      ghost_review = create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 4, metric_version_id: v1.id)
      v1.delete
      expect(run.stale_review_summary).to eq({})
    end

    it "skips reviews on a metric that has no current published version" do
      run = create(:completion_kit_run)
      metric = create(:completion_kit_metric)
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      response = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 4, metric_version_id: v1.id)
      CompletionKit::MetricVersion.where(metric_id: metric.id).update_all(current: false)
      expect(run.stale_review_summary).to eq({})
    end
  end

  describe "#metrics" do
    it "returns empty array when no metrics associated" do
      run = create(:completion_kit_run)
      expect(run.metrics).to eq([])
    end

    it "returns associated metrics ordered by position" do
      run = create(:completion_kit_run)
      m1 = create(:completion_kit_metric, name: "Second")
      m2 = create(:completion_kit_metric, name: "First")
      CompletionKit::RunMetric.create!(run: run, metric: m1, position: 2)
      CompletionKit::RunMetric.create!(run: run, metric: m2, position: 1)
      expect(run.metrics.map(&:name)).to eq(["First", "Second"])
    end
  end

  describe "broadcast helpers" do
    let(:prompt) { create(:completion_kit_prompt) }
    let(:run) { create(:completion_kit_run, prompt: prompt) }

    before do
      allow(run).to receive(:broadcast_ui).and_call_original
      allow(run).to receive(:broadcast_progress).and_call_original
      allow(run).to receive(:broadcast_response).and_call_original
      allow(run).to receive(:broadcast_response_update).and_call_original
      allow(run).to receive(:broadcast_status_header).and_call_original
      allow(run).to receive(:broadcast_actions).and_call_original
      allow(run).to receive(:broadcast_sort_toolbar).and_call_original
      allow(run).to receive(:broadcast_replace_to)
      allow(run).to receive(:broadcast_append_to)
    end

    it "broadcast_ui dispatches to the four sub-broadcasts" do
      run.broadcast_ui
      expect(run).to have_received(:broadcast_progress)
      expect(run).to have_received(:broadcast_status_header).at_least(:once)
      expect(run).to have_received(:broadcast_actions)
      expect(run).to have_received(:broadcast_sort_toolbar)
    end

    it "broadcast_progress calls broadcast_replace_to with run_status_panel target" do
      run.send(:broadcast_progress)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_status_panel")
      )
    end

    it "broadcast_response calls broadcast_append_to with run_responses target" do
      response = run.responses.create!(response_text: "test")
      run.send(:broadcast_response, response)
      expect(run).to have_received(:broadcast_append_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_responses")
      )
    end

    it "broadcast_response_update calls broadcast_replace_to with response target" do
      response = run.responses.create!(response_text: "test")
      run.broadcast_response_update(response)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "response_#{response.id}")
      ).at_least(:once)
    end

    it "broadcast_status_header calls broadcast_replace_to with run_status_header target" do
      run.send(:broadcast_status_header)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_status_header")
      )
    end

    it "broadcast_actions calls broadcast_replace_to with run_actions target" do
      run.send(:broadcast_actions)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_actions")
      )
    end

    it "broadcast_sort_toolbar calls broadcast_replace_to with run_sort_toolbar target" do
      allow(run).to receive(:broadcast_sort_toolbar).and_call_original
      run.send(:broadcast_sort_toolbar)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_sort_toolbar")
      )
    end

    it "broadcast_clear_responses calls broadcast_replace_to with run_responses target" do
      allow(run).to receive(:broadcast_clear_responses).and_call_original
      run.send(:broadcast_clear_responses)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_responses")
      )
    end
  end

  describe "#start!" do
    let(:prompt) { create(:completion_kit_prompt, template: "Static prompt with no variables") }
    let(:client) { instance_double(CompletionKit::LlmClient, configured?: true, configuration_errors: []) }

    before do
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
      allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
    end

    it "creates pending Responses and enqueues GenerateRowJob for each row" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil)

      result = run.start!

      expect(result).to be true
      expect(run.responses.count).to eq(1)
      expect(run.responses.first.status).to eq("pending")
      expect(CompletionKit::GenerateRowJob).to have_received(:perform_later).once
    end

    it "refuses to restart a running run and leaves its responses alone (prevents data loss from a stray POST /generate)" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil, status: "running")
      existing = create(:completion_kit_response, run: run, status: "succeeded")

      result = run.start!

      expect(result).to be false
      expect(CompletionKit::Response.where(id: existing.id)).to exist
      expect(run.reload.failure_summary).to include("Cannot start a run")
    end

    it "refuses to restart a completed run (use rerun instead)" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil, status: "completed")
      existing = create(:completion_kit_response, run: run, status: "succeeded")

      result = run.start!

      expect(result).to be false
      expect(CompletionKit::Response.where(id: existing.id)).to exist
    end

    it "still allows restarting a failed run (Retry button path)" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil, status: "failed")
      result = run.start!
      expect(result).to be true
      expect(run.reload.status).to eq("running")
    end

    it "transitions status to running" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil)

      run.start!

      expect(run.reload.status).to eq("running")
    end

    it "still reports success when the post-start UI broadcast raises (no started run leaks as an API error)" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil)
      allow(run).to receive(:broadcast_ui)
        .and_raise(ActionController::UrlGenerationError.new("missing required keys: [:org_slug]"))

      expect(run.start!).to be(true)
      expect(run.reload.status).to eq("running")
      expect(CompletionKit::GenerateRowJob).to have_received(:perform_later).once
    end

    it "returns false and sets failure_summary when dataset has no rows" do
      dataset = create(:completion_kit_dataset, csv_data: "header\n")
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset)
      allow(CompletionKit::CsvProcessor).to receive(:process_self).and_return([])

      result = run.start!

      expect(result).to be false
      expect(run.reload.status).to eq("failed")
      expect(run.reload.failure_summary).to include("Dataset has no rows")
    end

    it "returns false and sets failure_summary when LLM client is not configured" do
      bad_client = instance_double(CompletionKit::LlmClient, configured?: false, configuration_errors: ["API key missing"])
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(bad_client)
      run = create(:completion_kit_run, prompt: prompt, dataset: nil)

      result = run.start!

      expect(result).to be false
      expect(run.reload.status).to eq("failed")
      expect(run.reload.failure_summary).to include("LLM API not configured")
    end

    it "returns false without persisting when run is not persisted and LLM is unconfigured" do
      bad_client = instance_double(CompletionKit::LlmClient, configured?: false, configuration_errors: ["API key missing"])
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(bad_client)
      run = build(:completion_kit_run, prompt: prompt, dataset: nil)

      result = run.start!

      expect(result).to be false
      expect(run).not_to be_persisted
    end
  end

  describe "judge-only runs" do
    let(:metric) { create(:completion_kit_metric, name: "Quality") }
    let(:dataset_with_output) do
      create(:completion_kit_dataset, csv_data: "input,actual_output\nWhat is 2+2?,4\nWhat is 1+1?,2\n")
    end
    let(:dataset_without_output) do
      create(:completion_kit_dataset, csv_data: "input,response\nWhat is 2+2?,four\n")
    end

    describe "#judge_only?" do
      it "is true when no prompt is associated" do
        run = build(:completion_kit_run, prompt: nil, dataset: dataset_with_output)
        expect(run.judge_only?).to eq(true)
      end

      it "is false when a prompt is associated" do
        run = build(:completion_kit_run)
        expect(run.judge_only?).to eq(false)
      end
    end

    describe "auto-generated name" do
      it "names an unnamed scoring run after its dataset" do
        dataset = create(:completion_kit_dataset, name: "Tickets", csv_data: "input,actual_output\nhi,hello\n")
        run = create(:completion_kit_run, prompt: nil, dataset: dataset, output_column: "actual_output", name: nil)
        expect(run.name).to eq("Tickets scoring #1")
      end
    end

    describe "validations" do
      it "requires a dataset for a judge-only run" do
        run = build(:completion_kit_run, prompt: nil, dataset: nil)
        expect(run).not_to be_valid
        expect(run.errors[:dataset_id].join).to include("required when scoring existing outputs")
      end

      it "rejects a judge-only run whose output_column is not on the dataset" do
        run = build(:completion_kit_run, prompt: nil, dataset: dataset_without_output, output_column: "actual_output")
        expect(run).not_to be_valid
        expect(run.errors[:output_column].join).to include("is not a column on dataset")
      end

      it "accepts a judge-only run with a valid output_column" do
        run = build(:completion_kit_run, prompt: nil, dataset: dataset_with_output, output_column: "actual_output")
        expect(run).to be_valid
      end

      it "defaults to the actual_output column when output_column is blank" do
        run = build(:completion_kit_run, prompt: nil, dataset: dataset_with_output, output_column: nil)
        expect(run).to be_valid
      end
    end

    describe "#start!" do
      let(:run) do
        run = create(:completion_kit_run, prompt: nil, dataset: dataset_with_output, judge_model: "gpt-4o")
        CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
        run
      end

      before do
        allow(CompletionKit::JudgeReviewJob).to receive(:perform_later)
        allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
        allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
        allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true)
      end

      it "marks every response succeeded with response_text from the output_column and skips GenerateRowJob" do
        result = run.start!

        expect(result).to be true
        expect(run.responses.count).to eq(2)
        expect(run.responses.pluck(:status).uniq).to eq(["succeeded"])
        expect(run.responses.pluck(:response_text)).to match_array(%w[4 2])
        expect(CompletionKit::GenerateRowJob).not_to have_received(:perform_later)
      end

      it "enqueues JudgeReviewJob per response per metric when judging is configured" do
        run.start!

        expect(CompletionKit::JudgeReviewJob).to have_received(:perform_later).twice
      end

      it "skips JudgeReviewJob when no judge is configured but still creates succeeded responses" do
        bare = create(:completion_kit_run, prompt: nil, dataset: dataset_with_output, judge_model: nil)

        bare.start!

        expect(bare.responses.pluck(:status).uniq).to eq(["succeeded"])
        expect(CompletionKit::JudgeReviewJob).not_to have_received(:perform_later)
      end

      it "enqueues RunCompletionCheckJob once" do
        run.start!

        expect(CompletionKit::RunCompletionCheckJob).to have_received(:perform_later).with(run.id)
      end

      it "fails with a summary when the dataset is missing the output_column" do
        mismatched = build(:completion_kit_run, prompt: nil, dataset: dataset_with_output, output_column: "expected_output")
        mismatched.save(validate: false)

        result = mismatched.start!

        expect(result).to be false
        expect(mismatched.reload.status).to eq("failed")
        expect(mismatched.reload.failure_summary).to include("Dataset has no \"expected_output\" column")
      end
    end
  end

  describe "check metric execution" do
    let(:check_metric) do
      create(:completion_kit_metric, :check, check_config: { "check_kind" => "contains", "target" => "response_text", "value" => "ok" })
    end
    let(:llm_metric) { create(:completion_kit_metric, name: "Quality") }

    describe "#llm_judge_configured? and #gradable?" do
      before { allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true) }

      it "llm_judge_configured? is false for a check-only run with a judge_model but no llm metric" do
        run = create(:completion_kit_run, judge_model: "gpt-4o")
        run.run_metrics.create!(metric: check_metric, position: 1)
        expect(run.llm_judge_configured?).to be(false)
        expect(run.gradable?).to be(true)
      end

      it "llm_judge_configured? is true with a judge_model, an llm metric, and a valid model" do
        run = create(:completion_kit_run, judge_model: "gpt-4o")
        run.run_metrics.create!(metric: llm_metric, position: 1)
        expect(run.llm_judge_configured?).to be(true)
        expect(run.gradable?).to be(true)
      end

      it "gradable? is false for an llm-only run with no judge_model" do
        run = create(:completion_kit_run, judge_model: nil)
        run.run_metrics.create!(metric: llm_metric, position: 1)
        expect(run.gradable?).to be(false)
      end
    end

    describe "#start! dispatch" do
      before do
        allow(CompletionKit::JudgeReviewJob).to receive(:perform_later)
        allow(CompletionKit::CheckReviewJob).to receive(:perform_later)
        allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
        allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
        allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true)
      end

      it "dispatches CheckReviewJob (not JudgeReviewJob) for a check-only judge-only run with no judge_model" do
        dataset = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")
        run = create(:completion_kit_run, prompt: nil, dataset: dataset, judge_model: nil)
        run.run_metrics.create!(metric: check_metric, position: 1)

        expect(run.start!).to be(true)
        expect(CompletionKit::CheckReviewJob).to have_received(:perform_later).once
        expect(CompletionKit::JudgeReviewJob).not_to have_received(:perform_later)
        expect(CompletionKit::RunCompletionCheckJob).to have_received(:perform_later).with(run.id)
      end

      it "dispatches both job types for a mixed judge-only run" do
        dataset = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")
        run = create(:completion_kit_run, prompt: nil, dataset: dataset, judge_model: "gpt-4o")
        run.run_metrics.create!(metric: llm_metric, position: 1)
        run.run_metrics.create!(metric: check_metric, position: 2)

        run.start!

        expect(CompletionKit::JudgeReviewJob).to have_received(:perform_later).once
        expect(CompletionKit::CheckReviewJob).to have_received(:perform_later).once
      end
    end

    describe "an input_data-only check run needs no output column" do
      let(:input_check) do
        create(:completion_kit_metric, :check, check_config: { "check_kind" => "valid_json", "target" => "input_data" })
      end
      let(:dataset_no_output) { create(:completion_kit_dataset, csv_data: "input,topic\nhello,greeting\n") }

      before do
        allow(CompletionKit::CheckReviewJob).to receive(:perform_later)
        allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
      end

      it "is valid and starts with succeeded responses carrying nil response_text" do
        run = CompletionKit::Run.new(prompt: nil, dataset: dataset_no_output, name: "input check")
        run.run_metrics.build(metric: input_check, position: 1)

        expect(run).to be_valid
        run.save!

        expect(run.start!).to be(true)
        expect(run.responses.pluck(:status).uniq).to eq(["succeeded"])
        expect(run.responses.first.response_text).to be_nil
        expect(CompletionKit::CheckReviewJob).to have_received(:perform_later).once
      end

      it "regrades despite nil response_text on its responses" do
        run = CompletionKit::Run.new(prompt: nil, dataset: dataset_no_output, name: "input check")
        run.run_metrics.build(metric: input_check, position: 1)
        run.save!
        response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: nil)

        expect(run.regrade!).to be(true)
        expect(CompletionKit::CheckReviewJob).to have_received(:perform_later).with(response_row.id, input_check.id, run.id)
      end
    end

    describe "#regrade! with checks" do
      before do
        allow(CompletionKit::CheckReviewJob).to receive(:perform_later)
        allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
      end

      it "is gated on gradable?, clears passed, and re-dispatches CheckReviewJob" do
        run = create(:completion_kit_run, judge_model: nil)
        run.run_metrics.create!(metric: check_metric, position: 1)
        response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
        v1 = CompletionKit::MetricVersion.ensure_current_for(check_metric)
        review = response_row.reviews.create!(metric: check_metric, metric_name: check_metric.name,
                                              metric_version_id: v1.id, status: "succeeded", passed: true, ai_score: nil)

        expect(run.regrade!).to be(true)
        expect(review.reload.passed).to be_nil
        expect(review.reload.status).to eq("pending")
        expect(CompletionKit::CheckReviewJob).to have_received(:perform_later).with(response_row.id, check_metric.id, run.id)
      end
    end

    describe "completion ignores an un-gradable llm metric" do
      it "does not count an llm metric with no configured judge in outstanding work" do
        run = create(:completion_kit_run, judge_model: nil, progress_total: 1)
        run.run_metrics.create!(metric: llm_metric, position: 1)
        run.run_metrics.create!(metric: check_metric, position: 2)
        response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
        response_row.reviews.create!(metric: check_metric, metric_name: check_metric.name,
                                    metric_version_id: CompletionKit::MetricVersion.ensure_current_for(check_metric).id,
                                    status: "succeeded", passed: true, ai_score: nil)

        expect(run.outstanding_work_zero?).to be(true)
      end

      it "reports the check as judged_done in progress even though an un-gradable llm metric is attached" do
        run = create(:completion_kit_run, judge_model: nil, progress_total: 1)
        run.run_metrics.create!(metric: llm_metric, position: 1)
        run.run_metrics.create!(metric: check_metric, position: 2)
        response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
        response_row.reviews.create!(metric: check_metric, metric_name: check_metric.name,
                                    metric_version_id: CompletionKit::MetricVersion.ensure_current_for(check_metric).id,
                                    status: "succeeded", passed: true, ai_score: nil)

        expect(run.progress_snapshot[:judged_done]).to eq(1)
      end
    end

    describe "#progress_snapshot with checks" do
      it "counts a succeeded check review as judged_done" do
        run = create(:completion_kit_run, judge_model: nil, progress_total: 1)
        run.run_metrics.create!(metric: check_metric, position: 1)
        response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
        v1 = CompletionKit::MetricVersion.ensure_current_for(check_metric)
        response_row.reviews.create!(metric: check_metric, metric_name: check_metric.name,
                                    metric_version_id: v1.id, status: "succeeded", passed: true, ai_score: nil)

        expect(run.progress_snapshot[:judged_done]).to eq(1)
      end
    end
  end

  describe "#generate_responses!" do
    let(:prompt) { create(:completion_kit_prompt, template: "Static prompt with no variables") }
    let(:client) { instance_double(CompletionKit::LlmClient, configured?: true, configuration_errors: []) }

    before do
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
      allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
    end

    it "delegates to start! and returns true on success" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil)
      result = run.generate_responses!
      expect(result).to be true
    end
  end

  describe "dataset_supplies_prompt_variables validation" do
    let(:prompt_with_vars) { create(:completion_kit_prompt, template: "Hello {{name}}, regarding {{topic}}") }
    let(:prompt_without_vars) { create(:completion_kit_prompt, template: "Static prompt") }

    it "rejects a run when prompt has variables and no dataset is supplied" do
      run = build(:completion_kit_run, prompt: prompt_with_vars, dataset: nil)
      expect(run).not_to be_valid
      expect(run.errors[:dataset_id].join).to include("name").and include("topic")
    end

    it "rejects a run when dataset is missing required columns" do
      dataset = create(:completion_kit_dataset, csv_data: "name,other\nfoo,bar\n")
      run = build(:completion_kit_run, prompt: prompt_with_vars, dataset: dataset)
      expect(run).not_to be_valid
      expect(run.errors[:dataset_id].join).to include("topic")
    end

    it "accepts a run when all variables are present in dataset headers" do
      dataset = create(:completion_kit_dataset, csv_data: "name,topic\nfoo,bar\n")
      run = build(:completion_kit_run, prompt: prompt_with_vars, dataset: dataset)
      expect(run).to be_valid
    end

    it "accepts a run with no dataset when prompt has no variables" do
      run = build(:completion_kit_run, prompt: prompt_without_vars, dataset: nil)
      expect(run).to be_valid
    end
  end

  describe "#outstanding_work_zero?" do
    let(:prompt) { create(:completion_kit_prompt) }
    let(:metric) { create(:completion_kit_metric) }

    before { allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true) }

    it "returns true when all responses are terminal and no metrics" do
      run = create(:completion_kit_run, prompt: prompt)
      run.responses.create!(status: "succeeded", response_text: "done")
      expect(run.outstanding_work_zero?).to be true
    end

    it "returns false when a response is non-terminal" do
      run = create(:completion_kit_run, prompt: prompt)
      run.responses.create!(status: "pending")
      expect(run.outstanding_work_zero?).to be false
    end

    it "returns false when a response is succeeded but review is non-terminal" do
      run = create(:completion_kit_run, prompt: prompt, judge_model: "gpt-4o")
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
      response = run.responses.create!(status: "succeeded", response_text: "done")
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      response.reviews.create!(metric: metric, status: "pending", metric_name: metric.name, metric_version: v1)
      expect(run.outstanding_work_zero?).to be false
    end

    it "returns true when all responses and reviews are terminal" do
      run = create(:completion_kit_run, prompt: prompt, judge_model: "gpt-4o")
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
      response = run.responses.create!(status: "succeeded", response_text: "done")
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      response.reviews.create!(metric: metric, status: "succeeded", metric_name: metric.name, metric_version: v1)
      expect(run.outstanding_work_zero?).to be true
    end

    it "returns true when metrics exist but all responses failed (no succeeded responses)" do
      run = create(:completion_kit_run, prompt: prompt, judge_model: "gpt-4o")
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
      run.responses.create!(status: "failed")
      expect(run.outstanding_work_zero?).to be true
    end
  end

  describe "#progress_snapshot" do
    let(:prompt) { create(:completion_kit_prompt) }
    let(:metric) { create(:completion_kit_metric) }

    before { allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true) }

    it "returns correct counts for both phases" do
      run = create(:completion_kit_run, prompt: prompt, judge_model: "gpt-4o", progress_total: 3)
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)

      r1 = run.responses.create!(status: "succeeded", response_text: "done")
      run.responses.create!(status: "failed")
      run.responses.create!(status: "pending")

      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      r1.reviews.create!(metric: metric, status: "succeeded", metric_name: metric.name, metric_version: v1)

      snapshot = run.progress_snapshot

      expect(snapshot[:generated_done]).to eq(1)
      expect(snapshot[:generated_failed]).to eq(1)
      expect(snapshot[:generated_total]).to eq(3)
      expect(snapshot[:judged_done]).to eq(1)
      expect(snapshot[:judged_failed]).to eq(0)
      expect(snapshot[:judged_total]).to eq(1)
    end

    it "does not count a row as judged_done until all metric reviews are terminal" do
      metric_a = create(:completion_kit_metric, name: "A")
      metric_b = create(:completion_kit_metric, name: "B")
      run = create(:completion_kit_run, prompt: prompt, judge_model: "gpt-4o", progress_total: 1)
      CompletionKit::RunMetric.create!(run: run, metric: metric_a, position: 1)
      CompletionKit::RunMetric.create!(run: run, metric: metric_b, position: 2)

      r1 = run.responses.create!(status: "succeeded", response_text: "done")
      r1.reviews.create!(metric: metric_a, status: "succeeded", metric_name: metric_a.name,
                         metric_version: CompletionKit::MetricVersion.ensure_current_for(metric_a))
      r1.reviews.create!(metric: metric_b, status: "pending", metric_name: metric_b.name,
                         metric_version: CompletionKit::MetricVersion.ensure_current_for(metric_b))

      snapshot = run.progress_snapshot

      expect(snapshot[:judged_total]).to eq(1)
      expect(snapshot[:judged_done]).to eq(0)
      expect(snapshot[:judged_failed]).to eq(0)
    end

    it "counts a row as judged_failed when any of its metric reviews failed" do
      metric_a = create(:completion_kit_metric, name: "A")
      metric_b = create(:completion_kit_metric, name: "B")
      run = create(:completion_kit_run, prompt: prompt, judge_model: "gpt-4o", progress_total: 1)
      CompletionKit::RunMetric.create!(run: run, metric: metric_a, position: 1)
      CompletionKit::RunMetric.create!(run: run, metric: metric_b, position: 2)

      r1 = run.responses.create!(status: "succeeded", response_text: "done")
      r1.reviews.create!(metric: metric_a, status: "succeeded", metric_name: metric_a.name,
                         metric_version: CompletionKit::MetricVersion.ensure_current_for(metric_a))
      r1.reviews.create!(metric: metric_b, status: "failed", metric_name: metric_b.name,
                         metric_version: CompletionKit::MetricVersion.ensure_current_for(metric_b))

      snapshot = run.progress_snapshot

      expect(snapshot[:judged_total]).to eq(1)
      expect(snapshot[:judged_done]).to eq(0)
      expect(snapshot[:judged_failed]).to eq(1)
    end
  end

  describe "status enum" do
    it "rejects the legacy generating status" do
      run = build(:completion_kit_run, status: "generating")
      expect(run).not_to be_valid
    end

    it "rejects the legacy judging status" do
      run = build(:completion_kit_run, status: "judging")
      expect(run).not_to be_valid
    end

    it "accepts running" do
      run = build(:completion_kit_run, status: "running")
      expect(run).to be_valid
    end
  end

end

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
      allow(run).to receive(:broadcast_progress).and_call_original
      allow(run).to receive(:broadcast_response).and_call_original
      allow(run).to receive(:broadcast_response_update).and_call_original
      allow(run).to receive(:broadcast_status_header).and_call_original
      allow(run).to receive(:broadcast_actions).and_call_original
      allow(run).to receive(:broadcast_replace_to)
      allow(run).to receive(:broadcast_append_to)
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
      run.send(:broadcast_response_update, response)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "response_#{response.id}")
      )
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

    it "transitions status to running" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil)

      run.start!

      expect(run.reload.status).to eq("running")
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

    describe "validations" do
      it "requires a dataset for a judge-only run" do
        run = build(:completion_kit_run, prompt: nil, dataset: nil)
        expect(run).not_to be_valid
        expect(run.errors[:dataset_id].join).to include("required for a judge-only run")
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
      run = create(:completion_kit_run, prompt: prompt)
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
      response = run.responses.create!(status: "succeeded", response_text: "done")
      response.reviews.create!(metric: metric, status: "pending", metric_name: metric.name)
      expect(run.outstanding_work_zero?).to be false
    end

    it "returns true when all responses and reviews are terminal" do
      run = create(:completion_kit_run, prompt: prompt)
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
      response = run.responses.create!(status: "succeeded", response_text: "done")
      response.reviews.create!(metric: metric, status: "succeeded", metric_name: metric.name)
      expect(run.outstanding_work_zero?).to be true
    end

    it "returns true when metrics exist but all responses failed (no succeeded responses)" do
      run = create(:completion_kit_run, prompt: prompt)
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
      run.responses.create!(status: "failed")
      expect(run.outstanding_work_zero?).to be true
    end
  end

  describe "#progress_snapshot" do
    let(:prompt) { create(:completion_kit_prompt) }
    let(:metric) { create(:completion_kit_metric) }

    it "returns correct counts for both phases" do
      run = create(:completion_kit_run, prompt: prompt, progress_total: 3)
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)

      r1 = run.responses.create!(status: "succeeded", response_text: "done")
      run.responses.create!(status: "failed")
      run.responses.create!(status: "pending")

      r1.reviews.create!(metric: metric, status: "succeeded", metric_name: metric.name)

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
      run = create(:completion_kit_run, prompt: prompt, progress_total: 1)
      CompletionKit::RunMetric.create!(run: run, metric: metric_a, position: 1)
      CompletionKit::RunMetric.create!(run: run, metric: metric_b, position: 2)

      r1 = run.responses.create!(status: "succeeded", response_text: "done")
      r1.reviews.create!(metric: metric_a, status: "succeeded", metric_name: metric_a.name)
      r1.reviews.create!(metric: metric_b, status: "pending", metric_name: metric_b.name)

      snapshot = run.progress_snapshot

      expect(snapshot[:judged_total]).to eq(1)
      expect(snapshot[:judged_done]).to eq(0)
      expect(snapshot[:judged_failed]).to eq(0)
    end

    it "counts a row as judged_failed when any of its metric reviews failed" do
      metric_a = create(:completion_kit_metric, name: "A")
      metric_b = create(:completion_kit_metric, name: "B")
      run = create(:completion_kit_run, prompt: prompt, progress_total: 1)
      CompletionKit::RunMetric.create!(run: run, metric: metric_a, position: 1)
      CompletionKit::RunMetric.create!(run: run, metric: metric_b, position: 2)

      r1 = run.responses.create!(status: "succeeded", response_text: "done")
      r1.reviews.create!(metric: metric_a, status: "succeeded", metric_name: metric_a.name)
      r1.reviews.create!(metric: metric_b, status: "failed", metric_name: metric_b.name)

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

require "rails_helper"

RSpec.describe "JSON serialization" do
  describe "Prompt#as_json" do
    let(:prompt) { create(:completion_kit_prompt) }

    it "includes expected attributes" do
      json = prompt.as_json
      expect(json.keys).to match_array(%i[id name description template llm_model family_key version_number current created_at updated_at tags])
    end
  end

  describe "Run#as_json" do
    let(:run) { create(:completion_kit_run) }

    it "includes expected attributes and computed fields" do
      json = run.as_json
      expect(json.keys).to include(:id, :name, :status, :prompt_id, :responses_count, :avg_score, :progress_current, :progress_total, :metric_ids)
    end

    it "computes responses_count" do
      run = create(:completion_kit_run)
      create(:completion_kit_response, run: run)
      expect(run.as_json[:responses_count]).to eq(1)
    end
  end

  describe "Dataset#as_json" do
    let(:dataset) { create(:completion_kit_dataset) }

    it "includes expected attributes" do
      json = dataset.as_json
      expect(json.keys).to match_array(%i[id name csv_data created_at updated_at tags])
    end
  end

  describe "Metric#as_json" do
    let(:metric) { create(:completion_kit_metric) }

    it "includes expected attributes" do
      json = metric.as_json
      expect(json.keys).to match_array(%i[id name key instruction rubric_bands metric_type created_at updated_at tags])
      expect(json[:metric_type]).to eq("llm_judge")
    end

    it "emits check_config and omits rubric_bands/instruction for a check" do
      json = create(:completion_kit_metric, :check).as_json
      expect(json.keys).to match_array(%i[id name key metric_type check_config created_at updated_at tags])
      expect(json[:metric_type]).to eq("check")
      expect(json[:check_config]).to include("check_kind" => "valid_json")
    end
  end

  describe "CompletionKit::MetricGroup#as_json" do
    let(:metric_group) { create(:completion_kit_metric_group, :with_metrics) }

    it "includes metric_ids" do
      json = metric_group.as_json
      expect(json.keys).to include(:metric_ids)
      expect(json[:metric_ids]).to be_an(Array)
      expect(json[:metric_ids].length).to be > 0
    end
  end

  describe "ProviderCredential#as_json" do
    let(:credential) { create(:completion_kit_provider_credential, api_key: "secret-key-123") }

    it "excludes api_key" do
      json = credential.as_json
      expect(json.keys).not_to include(:api_key)
      expect(json.keys).to match_array(%i[id provider api_endpoint created_at updated_at])
    end
  end

  describe "CompletionKit::Response#as_json" do
    it "includes expected attributes and computed fields" do
      resp = create(:completion_kit_response)
      json = resp.as_json
      expect(json.keys).to match_array(%i[id run_id input_data response_text expected_output created_at score reviewed reviews status attempts row_index error])
    end

    it "includes nested reviews" do
      resp = create(:completion_kit_response)
      create(:completion_kit_review, response: resp, ai_score: 4.0, ai_feedback: "Good")
      json = resp.as_json
      expect(json[:reviews].length).to eq(1)
      expect(json[:reviews].first[:ai_score].to_f).to eq(4.0)
    end
  end

  describe "CompletionKit::Review#as_json" do
    let(:review) { create(:completion_kit_review) }

    it "includes expected attributes" do
      json = review.as_json
      expect(json.keys).to match_array(%i[id response_id metric_id metric_version_id metric_name ai_score ai_feedback status attempts error])
    end
  end
end

RSpec.describe "Run#as_json includes progress object and failed_response_ids" do
  before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_ui)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_status_header)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_actions)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_sort_toolbar)
  end

  let(:run) { create(:completion_kit_run, progress_total: 2) }

  it "includes a progress hash with generated and judged sub-objects" do
    create(:completion_kit_response, run: run, status: "succeeded", response_text: "a")
    create(:completion_kit_response, :failed, run: run)

    payload = run.as_json
    expect(payload[:progress][:generated]).to include(done: 1, total: 2, failed: 1)
    expect(payload[:progress][:judged]).to include(done: 0, total: 0, failed: 0)
    expect(payload[:failed_response_ids]).to be_an(Array)
    expect(payload[:failed_response_ids].size).to eq(1)
  end

  it "preserves legacy progress_current and progress_total fields mapped to generated counters" do
    create(:completion_kit_response, run: run, status: "succeeded", response_text: "a")
    create(:completion_kit_response, run: run, status: "succeeded", response_text: "b")
    payload = run.as_json
    expect(payload).to have_key(:progress_current)
    expect(payload).to have_key(:progress_total)
    expect(payload[:progress_current]).to eq(2)
    expect(payload[:progress_total]).to eq(2)
  end

  it "includes failure_summary key" do
    payload = run.as_json
    expect(payload).to have_key(:failure_summary)
  end
end

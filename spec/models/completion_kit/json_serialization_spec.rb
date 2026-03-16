require "rails_helper"

RSpec.describe "JSON serialization" do
  describe "Prompt#as_json" do
    let(:prompt) { create(:completion_kit_prompt) }

    it "includes expected attributes" do
      json = prompt.as_json
      expect(json.keys).to match_array(%i[id name description template llm_model family_key version_number current created_at updated_at])
    end
  end

  describe "Run#as_json" do
    let(:run) { create(:completion_kit_run) }

    it "includes expected attributes and computed fields" do
      json = run.as_json
      expect(json.keys).to include(:id, :name, :status, :prompt_id, :responses_count, :avg_score)
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
      expect(json.keys).to match_array(%i[id name csv_data created_at updated_at])
    end
  end

  describe "Metric#as_json" do
    let(:metric) { create(:completion_kit_metric) }

    it "includes expected attributes" do
      json = metric.as_json
      expect(json.keys).to match_array(%i[id name key criteria evaluation_steps rubric_bands created_at updated_at])
    end
  end

  describe "CompletionKit::Criteria#as_json" do
    let(:criteria) { create(:completion_kit_criteria, :with_metrics) }

    it "includes metric_ids" do
      json = criteria.as_json
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
      expect(json.keys).to match_array(%i[id run_id input_data response_text expected_output created_at score reviewed reviews])
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
      expect(json.keys).to match_array(%i[id response_id metric_id metric_name ai_score ai_feedback status])
    end
  end
end

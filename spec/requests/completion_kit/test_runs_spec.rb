require "rails_helper"

RSpec.describe "CompletionKit test runs", type: :request do
  let!(:prompt) { create(:completion_kit_prompt, name: "Prompt A") }
  let(:base_path) { "/completion_kit/test_runs" }
  let(:csv_data) do
    <<~CSV
      content,audience,expected_output
      "Release notes","developers","A developer summary"
    CSV
  end

  it "renders index, show, new, and edit pages across sort branches" do
    test_run = create(:completion_kit_test_run, prompt: prompt, name: "Run A")
    create(:completion_kit_test_result, test_run: test_run, quality_score: 8.0, created_at: 2.days.ago)
    create(:completion_kit_test_result, test_run: test_run, quality_score: 2.0, created_at: 1.day.ago)

    get base_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Run A")

    %w[score_desc score_asc created_desc created_asc unexpected].each do |sort|
      get "#{base_path}/#{test_run.id}", params: { sort: sort }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Run A")
    end

    get "#{base_path}/new", params: { prompt_id: prompt.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Paste your CSV here")

    get "#{base_path}/#{test_run.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Run A")
  end

  it "creates a test run with valid params" do
    expect do
      post base_path, params: { test_run: { prompt_id: prompt.id, name: "Created Run", csv_data: csv_data } }
    end.to change(CompletionKit::TestRun, :count).by(1)

    expect(response).to redirect_to("/completion_kit/test_runs")
  end

  it "renders new when create is invalid" do
    post base_path, params: { test_run: { prompt_id: prompt.id, name: "", csv_data: "bad" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("prevented this CSV run from being saved")
  end

  it "updates a test run with valid params" do
    test_run = create(:completion_kit_test_run, prompt: prompt, name: "Old Run")

    patch "#{base_path}/#{test_run.id}", params: { test_run: { prompt_id: prompt.id, name: "New Run", csv_data: csv_data } }

    expect(response).to redirect_to("/completion_kit/test_runs")
    expect(test_run.reload.name).to eq("New Run")
  end

  it "renders edit when update is invalid" do
    test_run = create(:completion_kit_test_run, prompt: prompt)

    patch "#{base_path}/#{test_run.id}", params: { test_run: { prompt_id: prompt.id, name: "", csv_data: "" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("prevented this CSV run from being saved")
  end

  it "destroys a test run" do
    test_run = create(:completion_kit_test_run, prompt: prompt)

    expect do
      delete "#{base_path}/#{test_run.id}"
    end.to change(CompletionKit::TestRun, :count).by(-1)

    expect(response).to redirect_to("/completion_kit/test_runs")
  end

  it "runs a test run successfully" do
    test_run = create(:completion_kit_test_run, prompt: prompt)

    allow_any_instance_of(CompletionKit::TestRun).to receive(:run_tests).and_return(true)

    post "#{base_path}/#{test_run.id}/run"

    expect(response).to redirect_to("/completion_kit/test_runs/#{test_run.id}")
  end

  it "handles run failure with model errors" do
    test_run = create(:completion_kit_test_run, prompt: prompt)

    allow_any_instance_of(CompletionKit::TestRun).to receive(:run_tests) do |instance|
      instance.errors.add(:base, "run failed")
      false
    end

    post "#{base_path}/#{test_run.id}/run"

    expect(response).to redirect_to("/completion_kit/test_runs/#{test_run.id}")
  end

  it "evaluates results successfully" do
    test_run = create(:completion_kit_test_run, prompt: prompt)

    allow_any_instance_of(CompletionKit::TestRun).to receive(:evaluate_results).and_return(2)

    post "#{base_path}/#{test_run.id}/evaluate"

    expect(response).to redirect_to("/completion_kit/test_runs/#{test_run.id}")
  end

  it "handles evaluate failure" do
    test_run = create(:completion_kit_test_run, prompt: prompt)

    allow_any_instance_of(CompletionKit::TestRun).to receive(:evaluate_results).and_return(0)

    post "#{base_path}/#{test_run.id}/evaluate"

    expect(response).to redirect_to("/completion_kit/test_runs/#{test_run.id}")
  end
end

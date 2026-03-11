require "rails_helper"

RSpec.describe "CompletionKit runs", type: :request do
  let!(:prompt) { create(:completion_kit_prompt, name: "Prompt A") }
  let(:base_path) { "/completion_kit/runs" }

  it "renders index, show, new, and edit pages across sort branches" do
    run = create(:completion_kit_run, prompt: prompt, name: "Run A")
    r1 = create(:completion_kit_response, run: run)
    r2 = create(:completion_kit_response, run: run)
    create(:completion_kit_review, response: r1, ai_score: 4.0)
    create(:completion_kit_review, response: r2, ai_score: 2.0)

    get base_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Run A")

    %w[score_desc score_asc].each do |sort|
      get "#{base_path}/#{run.id}", params: { sort: sort }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Run A")
    end

    get "#{base_path}/#{run.id}"
    expect(response).to have_http_status(:ok)

    get "#{base_path}/new", params: { prompt_id: prompt.id }
    expect(response).to have_http_status(:ok)

    get "#{base_path}/#{run.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Run A")
  end

  it "creates a run with valid params" do
    dataset = create(:completion_kit_dataset)

    expect do
      post base_path, params: { run: { prompt_id: prompt.id, dataset_id: dataset.id } }
    end.to change(CompletionKit::Run, :count).by(1)

    expect(response).to redirect_to("/completion_kit/runs")
  end

  it "renders new when create is invalid" do
    post base_path, params: { run: { prompt_id: nil } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("prevented this run from being saved")
  end

  it "updates a run with valid params" do
    run = create(:completion_kit_run, prompt: prompt, name: "Old Run")
    dataset = create(:completion_kit_dataset)

    patch "#{base_path}/#{run.id}", params: { run: { prompt_id: prompt.id, dataset_id: dataset.id } }

    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
  end

  it "renders edit when update is invalid" do
    run = create(:completion_kit_run, prompt: prompt)

    allow_any_instance_of(CompletionKit::Run).to receive(:update) do |instance, _attrs|
      instance.errors.add(:base, "something went wrong")
      false
    end

    patch "#{base_path}/#{run.id}", params: { run: { prompt_id: prompt.id } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("prevented this run from being saved")
  end

  it "destroys a run" do
    run = create(:completion_kit_run, prompt: prompt)

    expect do
      delete "#{base_path}/#{run.id}"
    end.to change(CompletionKit::Run, :count).by(-1)

    expect(response).to redirect_to("/completion_kit/runs")
  end

  it "generates responses successfully" do
    run = create(:completion_kit_run, prompt: prompt)

    allow_any_instance_of(CompletionKit::Run).to receive(:generate_responses!).and_return(true)

    post "#{base_path}/#{run.id}/generate"

    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
  end

  it "handles generate failure with model errors" do
    run = create(:completion_kit_run, prompt: prompt)

    allow_any_instance_of(CompletionKit::Run).to receive(:generate_responses!) do |instance|
      instance.errors.add(:base, "generation failed")
      false
    end

    post "#{base_path}/#{run.id}/generate"

    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
  end

  it "judges responses successfully" do
    run = create(:completion_kit_run, prompt: prompt)

    allow_any_instance_of(CompletionKit::Run).to receive(:judge_responses!).and_return(true)

    post "#{base_path}/#{run.id}/judge"

    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
  end

  it "handles judge failure" do
    run = create(:completion_kit_run, prompt: prompt)

    allow_any_instance_of(CompletionKit::Run).to receive(:judge_responses!).and_return(false)

    post "#{base_path}/#{run.id}/judge"

    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
  end
end

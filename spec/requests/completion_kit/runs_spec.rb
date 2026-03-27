require "rails_helper"

RSpec.describe "CompletionKit runs", type: :request do
  let!(:prompt) { create(:completion_kit_prompt, name: "Prompt A") }
  let(:base_path) { "/completion_kit/runs" }

  it "renders index, show, new, and edit pages" do
    run = create(:completion_kit_run, prompt: prompt, name: "Run A")

    get base_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Run A")

    get "#{base_path}/#{run.id}"
    expect(response).to have_http_status(:ok)

    get "#{base_path}/new", params: { prompt_id: prompt.id }
    expect(response).to have_http_status(:ok)

    get "#{base_path}/#{run.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Run A")
  end

  it "sorts responses by score when judge is configured" do
    run = create(:completion_kit_run, prompt: prompt, name: "Run A")
    r1 = create(:completion_kit_response, run: run)
    r2 = create(:completion_kit_response, run: run)
    create(:completion_kit_review, response: r1, ai_score: 4.0)
    create(:completion_kit_review, response: r2, ai_score: 2.0)

    allow_any_instance_of(CompletionKit::Run).to receive(:judge_configured?).and_return(true)

    get "#{base_path}/#{run.id}", params: { sort: "score_asc" }
    expect(response).to have_http_status(:ok)

    get "#{base_path}/#{run.id}", params: { sort: "score_desc" }
    expect(response).to have_http_status(:ok)
  end

  it "orders responses by id when judge is not configured" do
    run = create(:completion_kit_run, prompt: prompt, name: "Run A")
    create(:completion_kit_response, run: run)

    allow_any_instance_of(CompletionKit::Run).to receive(:judge_configured?).and_return(false)

    get "#{base_path}/#{run.id}"
    expect(response).to have_http_status(:ok)
  end

  it "creates a run with valid params" do
    dataset = create(:completion_kit_dataset)

    expect do
      post base_path, params: { run: { prompt_id: prompt.id, dataset_id: dataset.id } }
    end.to change(CompletionKit::Run, :count).by(1)

    expect(response).to redirect_to(%r{/completion_kit/runs/\d+})
  end

  it "creates a run with metric_ids" do
    metric = create(:completion_kit_metric)

    expect do
      post base_path, params: { run: { prompt_id: prompt.id, metric_ids: [metric.id] } }
    end.to change(CompletionKit::Run, :count).by(1)

    run = CompletionKit::Run.last
    expect(run.metric_ids).to eq([metric.id])
    expect(response).to redirect_to(%r{/completion_kit/runs/\d+})
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

  it "updates a run with metric_ids" do
    run = create(:completion_kit_run, prompt: prompt)
    metric = create(:completion_kit_metric)

    patch "#{base_path}/#{run.id}", params: { run: { prompt_id: prompt.id, metric_ids: [metric.id] } }

    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
    expect(run.reload.metric_ids).to eq([metric.id])
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

  it "enqueues GenerateJob and redirects" do
    run = create(:completion_kit_run, prompt: prompt)
    post "#{base_path}/#{run.id}/generate"
    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
    follow_redirect!
    expect(response.body).to include("Generation started")
  end

  it "enqueues JudgeJob and redirects" do
    run = create(:completion_kit_run, prompt: prompt)
    post "#{base_path}/#{run.id}/judge"
    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
    follow_redirect!
    expect(response.body).to include("Judging started")
  end

  it "updates run params before judging when run params are present" do
    run = create(:completion_kit_run, prompt: prompt)

    post "#{base_path}/#{run.id}/judge", params: { run: { judge_model: "gpt-4.1" } }

    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
    expect(run.reload.judge_model).to eq("gpt-4.1")
  end
end

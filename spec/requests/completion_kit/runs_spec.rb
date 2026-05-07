require "rails_helper"

RSpec.describe "CompletionKit runs", type: :request do
  let!(:prompt) { create(:completion_kit_prompt, name: "Prompt A", template: "Static prompt without variables") }
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

  it "renders the show page with pending, retrying, and failed response rows" do
    run = create(:completion_kit_run, prompt: prompt, status: "running")
    create(:completion_kit_response, :pending, run: run)
    create(:completion_kit_response, :retrying, run: run)
    create(:completion_kit_response, :failed, run: run)

    get "#{base_path}/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Queued")
    expect(response.body).to include("Retrying")
    expect(response.body).to include("ck-chip--retry")
  end

  it "renders a failed response row with provider error details" do
    run = create(:completion_kit_run, prompt: prompt)
    create(:completion_kit_response, :failed, run: run, error_provider: "openai", error_status: 429, error_message: "Rate limit exceeded")

    get "#{base_path}/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Openai")
    expect(response.body).to include("429")
    expect(response.body).to include("Rate limit exceeded")
  end

  it "renders succeeded response with judging chip when run is still running and a judge is configured" do
    metric = create(:completion_kit_metric)
    run = create(:completion_kit_run, prompt: prompt, status: "running")
    run.replace_metrics!([metric.id])
    create(:completion_kit_response, run: run, status: "succeeded", response_text: "Output text")

    get "#{base_path}/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Judging")
  end

  it "renders Done chip on succeeded responses when the run has no judge configured" do
    run = create(:completion_kit_run, prompt: prompt, status: "completed")
    create(:completion_kit_response, run: run, status: "succeeded", response_text: "Output text")

    get "#{base_path}/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Done")
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

  it "creates a new run when updating a run with responses" do
    run = create(:completion_kit_run, prompt: prompt, name: "Original")
    run.responses.create!(response_text: "Some output")

    expect do
      patch "#{base_path}/#{run.id}", params: { run: { name: "Updated", prompt_id: prompt.id } }
    end.to change(CompletionKit::Run, :count).by(1)

    new_run = CompletionKit::Run.order(:id).last
    expect(new_run.name).to eq("Updated")
    expect(new_run.status).to eq("pending")
    expect(response).to redirect_to("/completion_kit/runs/#{new_run.id}")
    expect(run.reload.name).to eq("Original")
  end

  it "auto-renames the new run when the user did not change the name" do
    run = create(:completion_kit_run, prompt: prompt, name: "Property Summary — v1 #1")
    run.responses.create!(response_text: "Some output")

    patch "#{base_path}/#{run.id}", params: { run: { name: "Property Summary — v1 #1", prompt_id: prompt.id } }

    new_run = CompletionKit::Run.order(:id).last
    expect(new_run.name).not_to eq(run.name)
    expect(new_run.name).to match(/#2\z/)
  end

  it "carries metric_ids onto the new run when updating a run with responses" do
    run = create(:completion_kit_run, prompt: prompt, name: "Original")
    run.responses.create!(response_text: "Some output")
    metric = create(:completion_kit_metric)

    patch "#{base_path}/#{run.id}", params: { run: { name: "Updated", prompt_id: prompt.id, metric_ids: [metric.id] } }

    new_run = CompletionKit::Run.order(:id).last
    expect(new_run.metric_ids).to eq([metric.id])
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

  it "calls start! and redirects on success" do
    run = create(:completion_kit_run, prompt: prompt)
    expect_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(true)
    post "#{base_path}/#{run.id}/generate"
    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
  end

  it "redirects with alert when start! fails" do
    run = create(:completion_kit_run, prompt: prompt)
    allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(false)
    allow_any_instance_of(CompletionKit::Run).to receive(:failure_summary).and_return("Something went wrong")
    post "#{base_path}/#{run.id}/generate"
    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
    expect(flash[:alert]).to eq("Something went wrong")
  end

  it "rerun creates a new run with the same configuration and starts it" do
    metric = create(:completion_kit_metric)
    dataset = create(:completion_kit_dataset)
    source_run = create(:completion_kit_run, prompt: prompt, dataset: dataset, judge_model: "gpt-4.1", temperature: 0.3, status: "completed")
    source_run.replace_metrics!([metric.id])
    allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(true)

    expect { post "#{base_path}/#{source_run.id}/rerun" }
      .to change(CompletionKit::Run, :count).by(1)

    new_run = CompletionKit::Run.order(:id).last
    expect(new_run.id).not_to eq(source_run.id)
    expect(new_run.prompt_id).to eq(source_run.prompt_id)
    expect(new_run.dataset_id).to eq(source_run.dataset_id)
    expect(new_run.judge_model).to eq("gpt-4.1")
    expect(new_run.temperature).to eq(0.3)
    expect(new_run.metric_ids).to eq([metric.id])
    expect(response).to redirect_to("/completion_kit/runs/#{new_run.id}")
  end

  it "rerun redirects with an alert when start! fails on the new run" do
    source_run = create(:completion_kit_run, prompt: prompt, status: "completed")
    allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(false)
    allow_any_instance_of(CompletionKit::Run).to receive(:failure_summary).and_return("config gone")

    post "#{base_path}/#{source_run.id}/rerun"
    new_run = CompletionKit::Run.order(:id).last
    expect(response).to redirect_to("/completion_kit/runs/#{new_run.id}")
    expect(flash[:alert]).to eq("config gone")
  end

  it "refresh_status returns a turbo stream replacing the run status header" do
    run = create(:completion_kit_run, prompt: prompt, status: "running")
    get "#{base_path}/#{run.id}/refresh_status", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("turbo-stream")
    expect(response.body).to include("run_status_header")
  end

  it "suggest action creates a suggestion and redirects to its show page" do
    run = create(:completion_kit_run, prompt: prompt)
    service = instance_double(CompletionKit::PromptImprovementService)
    allow(CompletionKit::PromptImprovementService).to receive(:new).with(run).and_return(service)
    allow(service).to receive(:suggest).and_return({
      "reasoning" => "Improve clarity",
      "suggested_template" => "Better prompt",
      "original_template" => prompt.template
    })

    expect { post "#{base_path}/#{run.id}/suggest" }.to change(CompletionKit::Suggestion, :count).by(1)
    suggestion = CompletionKit::Suggestion.order(:id).last
    expect(response).to redirect_to("/completion_kit/suggestions/#{suggestion.id}?from=run")
  end
end

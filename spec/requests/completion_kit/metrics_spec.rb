require "rails_helper"

RSpec.describe "CompletionKit metrics", type: :request do
  let(:base_path) { "/completion_kit/metrics" }

  it "covers index, show, new, edit, create, update, invalid branches, and destroy" do
    metric = create(:completion_kit_metric, name: "Helpfulness")

    get base_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Helpfulness")

    get "#{base_path}/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Reasoning cue")

    get "#{base_path}/#{metric.id}"
    expect(response).to have_http_status(:ok)

    get "#{base_path}/#{metric.id}/edit"
    expect(response).to have_http_status(:ok)

    expect do
      post base_path, params: { metric: { name: "Accuracy", guidance_text: "Be exact" } }
    end.to change(CompletionKit::Metric, :count).by(1)
    expect(response).to redirect_to(%r{/completion_kit/metrics/\d+})

    post base_path, params: { metric: { name: "", rubric_text: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    patch "#{base_path}/#{metric.id}", params: { metric: { guidance_text: "Updated guidance" } }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
    expect(metric.reload.guidance_text).to eq("Updated guidance")

    patch "#{base_path}/#{metric.id}", params: { metric: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    expect do
      delete "#{base_path}/#{metric.id}"
    end.to change(CompletionKit::Metric, :count).by(-1)

    expect(response).to redirect_to("/completion_kit/metrics")
  end
end

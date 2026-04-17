require "rails_helper"

RSpec.describe "CompletionKit criteria", type: :request do
  let(:base_path) { "/completion_kit/criteria" }

  it "covers index, show, new, edit, create, update, invalid branches, and destroy" do
    metric = create(:completion_kit_metric, name: "Helpfulness")
    criteria = create(:completion_kit_criteria)

    get base_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(criteria.name)

    get "#{base_path}/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("A criteria groups metrics")

    get "#{base_path}/#{criteria.id}"
    expect(response).to have_http_status(:ok)

    get "#{base_path}/#{criteria.id}/edit"
    expect(response).to have_http_status(:ok)

    expect do
      post base_path, params: { criteria: { name: "QA pack", description: "Scoring pack", metric_ids: [metric.id] } }
    end.to change(CompletionKit::Criteria, :count).by(1)
    expect(response).to redirect_to(%r{/completion_kit/criteria/\d+})
    expect(CompletionKit::Criteria.order(:id).last.metrics).to eq([metric])

    post base_path, params: { criteria: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    patch "#{base_path}/#{criteria.id}", params: { criteria: { description: "Updated", metric_ids: [metric.id] } }
    expect(response).to redirect_to("/completion_kit/criteria/#{criteria.id}")
    expect(criteria.reload.description).to eq("Updated")
    expect(criteria.metrics).to eq([metric])

    patch "#{base_path}/#{criteria.id}", params: { criteria: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    expect do
      delete "#{base_path}/#{criteria.id}"
    end.to change(CompletionKit::Criteria, :count).by(-1)

    expect(response).to redirect_to("/completion_kit/criteria")
  end
end

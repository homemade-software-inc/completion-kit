require "rails_helper"

RSpec.describe "CompletionKit metric groups", type: :request do
  let(:base_path) { "/completion_kit/metric_groups" }

  it "covers index, show, new, edit, create, update, invalid branches, and destroy" do
    metric = create(:completion_kit_metric, name: "Helpfulness")
    metric_group = create(:completion_kit_metric_group)

    get base_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(metric_group.name)

    get "#{base_path}/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("A metric group only groups metrics")

    get "#{base_path}/#{metric_group.id}"
    expect(response).to have_http_status(:ok)

    get "#{base_path}/#{metric_group.id}/edit"
    expect(response).to have_http_status(:ok)

    expect do
      post base_path, params: { metric_group: { name: "QA pack", description: "Scoring pack", metric_ids: [metric.id] } }
    end.to change(CompletionKit::MetricGroup, :count).by(1)
    expect(response).to redirect_to(%r{/completion_kit/metric_groups/\d+})
    expect(CompletionKit::MetricGroup.order(:id).last.metrics).to eq([metric])

    post base_path, params: { metric_group: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    patch "#{base_path}/#{metric_group.id}", params: { metric_group: { description: "Updated", metric_ids: [metric.id] } }
    expect(response).to redirect_to("/completion_kit/metric_groups/#{metric_group.id}")
    expect(metric_group.reload.description).to eq("Updated")
    expect(metric_group.metrics).to eq([metric])

    patch "#{base_path}/#{metric_group.id}", params: { metric_group: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    expect do
      delete "#{base_path}/#{metric_group.id}"
    end.to change(CompletionKit::MetricGroup, :count).by(-1)

    expect(response).to redirect_to("/completion_kit/metric_groups")
  end
end

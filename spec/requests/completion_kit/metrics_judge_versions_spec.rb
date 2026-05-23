require "rails_helper"

RSpec.describe "CompletionKit metrics (judge versioning)", type: :request do
  let(:metric) { create(:completion_kit_metric, instruction: "score it") }

  before { CompletionKit::JudgeVersion.ensure_current_for(metric) }

  it "creates a draft judge version when the instruction changes" do
    expect {
      metric.update!(instruction: "score it carefully")
    }.to change { CompletionKit::JudgeVersion.drafts.where(metric_id: metric.id).count }.by(1)
  end

  it "does not create a draft when only the name changes" do
    expect {
      metric.update!(name: "renamed")
    }.not_to change { CompletionKit::JudgeVersion.drafts.where(metric_id: metric.id).count }
  end

  it "shows the draft banner on the metric show page" do
    metric.update!(instruction: "score it carefully")
    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).to include("Draft pending")
    expect(response.body).to include("Publish draft")
  end

  it "publishes the latest draft, demoting the previous published version" do
    metric.update!(instruction: "v2 instruction")
    previously_published = CompletionKit::JudgeVersion.published.where(metric_id: metric.id).first
    expect(previously_published).to be_present

    post "/completion_kit/metrics/#{metric.id}/publish_draft"
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
    follow_redirect!
    expect(response.body).to include("Draft published")

    versions = CompletionKit::JudgeVersion.where(metric_id: metric.id).order(:created_at).to_a
    expect(versions.map(&:state)).to eq(%w[published published])
    expect(versions.map(&:current)).to eq([false, true])
  end

  it "flashes an alert when there is no draft to publish" do
    post "/completion_kit/metrics/#{metric.id}/publish_draft"
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
    follow_redirect!
    expect(response.body).to include("No draft to publish")
  end

  it "rolls older drafts off current when a new draft fork happens" do
    metric.update!(instruction: "v2")
    metric.update!(instruction: "v3")
    drafts = CompletionKit::JudgeVersion.drafts.where(metric_id: metric.id).order(:created_at)
    expect(drafts.map(&:current)).to eq([false, false])
  end
end

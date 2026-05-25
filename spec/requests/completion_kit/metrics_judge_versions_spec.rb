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

  it "renders the Versions table on the metric show page with a Published chip on current and a Make current button on superseded published versions" do
    metric.update!(instruction: "v2 instruction")
    draft = CompletionKit::JudgeVersion.drafts.where(metric_id: metric.id).order(:created_at).last
    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: draft.id }
    follow_redirect!

    versions = CompletionKit::JudgeVersion.where(metric_id: metric.id).order(:version_number).to_a
    expect(versions.size).to eq(2)
    expect(versions.last.current?).to be(true)

    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).to include("Versions")
    expect(response.body).to include("ck-metric-versions-table")
    expect(response.body).to include(versions.last.version_label)
    expect(response.body).to include("Published")
    expect(response.body).to include("Make current")
    expect(response.body).to include("ck-cell-link--delta")
    expect(response.body).to include("ck-mvdiff-#{versions.last.id}")
  end

  it "lets the user revert to an older published version via Make current" do
    metric.update!(instruction: "v2 instruction")
    draft = CompletionKit::JudgeVersion.drafts.where(metric_id: metric.id).order(:created_at).last
    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: draft.id }
    follow_redirect!

    older = CompletionKit::JudgeVersion.where(metric_id: metric.id).order(:version_number).first
    expect(older.current?).to be(false)
    expect(older.published?).to be(true)

    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: older.id }
    expect(older.reload.current?).to be(true)
    expect(metric.reload.instruction).to eq(older.instruction)
  end

  it "shows a 'Review draft →' affordance on the metric show page and the draft banner on edit" do
    metric.update!(instruction: "score it carefully")
    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).not_to include("Draft pending")
    expect(response.body).to include("Review draft")

    get "/completion_kit/metrics/#{metric.id}/edit"
    expect(response.body).to include("Draft pending")
    expect(response.body).to include("Publish this version")
    expect(response.body).to include("Discard draft")
  end

  it "publishes the latest draft, demoting the previous published version" do
    metric.update!(instruction: "v2 instruction")
    previously_published = CompletionKit::JudgeVersion.published.where(metric_id: metric.id).first
    expect(previously_published).to be_present

    post "/completion_kit/metrics/#{metric.id}/publish_draft"
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
    follow_redirect!
    expect(response.body).to match(/v\d+ is now the published version/)

    versions = CompletionKit::JudgeVersion.where(metric_id: metric.id).order(:created_at).to_a
    expect(versions.map(&:state)).to eq(%w[published published])
    expect(versions.map(&:current)).to eq([false, true])
  end

  it "copies a published draft's instruction back into the metric so the judge actually uses it" do
    metric.update!(instruction: "v2 instruction")
    draft = CompletionKit::JudgeVersion.drafts.where(metric_id: metric.id).order(:created_at).last
    draft.update!(instruction: "the version we actually want")

    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: draft.id }
    expect(metric.reload.instruction).to eq("the version we actually want")
  end

  it "publishes the specific draft passed in draft_id, not just the newest" do
    metric.update!(instruction: "first edit")
    older = CompletionKit::JudgeVersion.drafts.where(metric_id: metric.id).order(:created_at).last
    metric.update!(instruction: "second edit")
    newer = CompletionKit::JudgeVersion.drafts.where(metric_id: metric.id).order(:created_at).last
    expect(newer.id).not_to eq(older.id)

    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: older.id }
    expect(older.reload.state).to eq("published")
    expect(newer.reload.state).to eq("draft")
  end

  it "flashes an alert when there is no draft to publish" do
    post "/completion_kit/metrics/#{metric.id}/publish_draft"
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
    follow_redirect!
    expect(response.body).to include("No version to publish")
  end

  it "rolls older drafts off current when a new draft fork happens" do
    metric.update!(instruction: "v2")
    metric.update!(instruction: "v3")
    drafts = CompletionKit::JudgeVersion.drafts.where(metric_id: metric.id).order(:created_at)
    expect(drafts.map(&:current)).to eq([false, false])
  end
end

require "rails_helper"

RSpec.describe "CompletionKit metrics (judge versioning)", type: :request do
  let(:metric) { create(:completion_kit_metric, instruction: "score it") }
  let(:run) { create(:completion_kit_run) }
  let(:response_row) { create(:completion_kit_response, run: run) }

  before do
    CompletionKit::MetricVersion.ensure_current_for(metric)
    create(:completion_kit_review, response: response_row, metric: metric, metric_name: metric.name, ai_score: 4)
  end

  def edit_metric_via_form(instruction: nil)
    attrs = { name: metric.name, instruction: instruction || "score it carefully" }
    patch "/completion_kit/metrics/#{metric.id}", params: { metric: attrs }
  end

  it "creates an edit-source draft judge version when the instruction changes via the form" do
    expect {
      edit_metric_via_form(instruction: "score it carefully")
    }.to change { CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "edit").count }.by(1)
  end

  it "does not create a draft when only the name changes" do
    expect {
      patch "/completion_kit/metrics/#{metric.id}", params: { metric: { name: "renamed", instruction: metric.instruction } }
    }.not_to change { CompletionKit::MetricVersion.drafts.where(metric_id: metric.id).count }
  end

  it "does not change metric.instruction in place when the metric has reviews — the change waits until publish" do
    edit_metric_via_form(instruction: "score it carefully")
    expect(metric.reload.instruction).to eq("score it")
  end

  it "writes the change in place when there are no reviews yet" do
    metric_without_reviews = create(:completion_kit_metric, instruction: "fresh")
    CompletionKit::MetricVersion.ensure_current_for(metric_without_reviews)
    patch "/completion_kit/metrics/#{metric_without_reviews.id}", params: { metric: { name: metric_without_reviews.name, instruction: "edited in place" } }
    expect(metric_without_reviews.reload.instruction).to eq("edited in place")
    current = CompletionKit::MetricVersion.current.find_by(metric_id: metric_without_reviews.id)
    expect(current.instruction).to eq("edited in place")
  end

  it "creates an edit draft when rubric_bands change via the form on a metric with reviews" do
    new_bands = (5).downto(1).map { |s| { "stars" => s, "description" => "band #{s} (revised)" } }
    expect {
      patch "/completion_kit/metrics/#{metric.id}", params: { metric: { name: metric.name, instruction: metric.instruction, rubric_bands: new_bands } }
    }.to change { CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "edit").count }.by(1)
    draft = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "edit").order(:created_at).last
    expect(draft.rubric_bands.first["description"]).to eq("band 5 (revised)")
    expect(metric.reload.rubric_bands).not_to eq(draft.rubric_bands)
  end

  it "updates rubric_bands in place and syncs the current published version when there are no reviews" do
    fresh = create(:completion_kit_metric, instruction: "fresh")
    CompletionKit::MetricVersion.ensure_current_for(fresh)
    new_bands = (5).downto(1).map { |s| { "stars" => s, "description" => "fresh band #{s}" } }
    patch "/completion_kit/metrics/#{fresh.id}", params: { metric: { name: fresh.name, instruction: fresh.instruction, rubric_bands: new_bands } }
    expect(fresh.reload.rubric_bands.first["description"]).to eq("fresh band 5")
    expect(CompletionKit::MetricVersion.current.find_by(metric_id: fresh.id).rubric_bands.first["description"]).to eq("fresh band 5")
  end

  it "normalizes rubric_bands whether they come in as plain hashes or as ActionController::Parameters" do
    ctrl = CompletionKit::MetricsController.new
    plain = [{ "stars" => 5, "description" => "top" }, { "stars" => 1, "description" => "bottom" }]
    result_plain = ctrl.send(:normalize_rubric_bands_for_update, plain)
    expect(result_plain.first["stars"]).to eq(5)
    expect(result_plain.first["description"]).to eq("top")

    params = ActionController::Parameters.new(rubric_bands: [{ stars: 4, description: "high" }, { stars: 2, description: "low" }])
    permitted = params.permit(rubric_bands: [:stars, :description])[:rubric_bands]
    result_perm = ctrl.send(:normalize_rubric_bands_for_update, permitted)
    expect(result_perm.first["stars"]).to eq(4)
    expect(result_perm.first["description"]).to eq("high")

    hash_shaped = ActionController::Parameters.new("0" => { "stars" => 3, "description" => "mid" }, "1" => { "stars" => 5, "description" => "top" })
    result_hash = ctrl.send(:normalize_rubric_bands_for_update, hash_shaped)
    expect(result_hash.first["stars"]).to eq(5)
    expect(result_hash.first["description"]).to eq("top")
  end

  it "pre-populates the edit form from the existing edit-draft so re-edits build on the unpublished work instead of clobbering it" do
    edit_metric_via_form(instruction: "the unpublished idea I want to keep iterating on")
    get "/completion_kit/metrics/#{metric.id}/edit"
    expect(response.body).to include("the unpublished idea I want to keep iterating on")
    expect(metric.reload.instruction).to eq("score it") # live state untouched
  end

  it "shows both the suggestion banner and the edit-draft banner on the edit form when both pending drafts exist" do
    edit_metric_via_form(instruction: "an in-flight edit")
    CompletionKit::MetricVersion.create!(metric: metric, instruction: "a separate model suggestion",
                                        rubric_bands: metric.rubric_bands || [],
                                        state: "draft", source: "suggestion", current: false)
    get "/completion_kit/metrics/#{metric.id}/edit"
    expect(response.body).to include("Draft pending")
    expect(response.body).to include("Proposed changes")
  end

  it "tolerates a fresh metric with no published MetricVersion when persisting an in-place edit" do
    fresh = create(:completion_kit_metric, instruction: "no-version-yet")
    CompletionKit::MetricVersion.where(metric_id: fresh.id).destroy_all
    expect {
      patch "/completion_kit/metrics/#{fresh.id}", params: { metric: { name: fresh.name, instruction: "edited" } }
    }.not_to raise_error
    expect(fresh.reload.instruction).to eq("edited")
  end

  it "renders the Versions table on the metric show page with a Published chip on current and a Make current button on superseded published versions" do
    edit_metric_via_form(instruction: "v2 instruction")
    draft = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id).order(:created_at).last
    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: draft.id }
    follow_redirect!

    versions = CompletionKit::MetricVersion.where(metric_id: metric.id).order(:version_number).to_a
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

  it "reverts to an older published version in place via Make current, creating no new version" do
    edit_metric_via_form(instruction: "v2 instruction")
    draft = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id).order(:created_at).last
    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: draft.id }
    follow_redirect!

    older = CompletionKit::MetricVersion.where(metric_id: metric.id).order(:version_number).first
    expect(older.current?).to be(false)
    expect(older.published?).to be(true)

    expect {
      post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: older.id }
    }.not_to change { CompletionKit::MetricVersion.where(metric_id: metric.id).count }

    expect(older.reload.current?).to be(true)
    expect(metric.reload.instruction).to eq(older.instruction)
    expect(CompletionKit::MetricVersion.where(metric_id: metric.id, source: "revert").count).to eq(0)
  end

  it "carries an in-place revert flash naming the version returned to and the one left behind" do
    edit_metric_via_form(instruction: "v2 instruction")
    new_draft = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "edit").order(:created_at).last
    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: new_draft.id }
    follow_redirect!

    older = CompletionKit::MetricVersion.where(metric_id: metric.id).order(:version_number).first
    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: older.id }
    follow_redirect!
    displaced = CompletionKit::MetricVersion.where(metric_id: metric.id).order(:version_number).last
    expect(response.body).to include("is back on #{older.version_label}")
    expect(response.body).to include("you gave on #{displaced.version_label}")
    expect(response.body).to include("stay with that version")
  end

  it "points a pending draft to the Versions table on the metric show page and shows the draft banner on edit" do
    edit_metric_via_form(instruction: "score it carefully")
    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).not_to include("Draft pending")
    expect(response.body).to include("waiting in the Versions table above")

    get "/completion_kit/metrics/#{metric.id}/edit"
    expect(response.body).to include("Draft pending")
    expect(response.body).to include("Publish this version")
    expect(response.body).to include("Discard draft")
  end

  it "publishes the latest draft, demoting the previous published version" do
    edit_metric_via_form(instruction: "v2 instruction")
    previously_published = CompletionKit::MetricVersion.published.where(metric_id: metric.id).first
    expect(previously_published).to be_present

    post "/completion_kit/metrics/#{metric.id}/publish_draft"
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
    follow_redirect!
    expect(response.body).to match(/v\d+ is now the published version/)

    versions = CompletionKit::MetricVersion.where(metric_id: metric.id).order(:created_at).to_a
    expect(versions.map(&:state)).to eq(%w[published published])
    expect(versions.map(&:current)).to eq([false, true])
  end

  it "copies a published draft's instruction back into the metric so the judge actually uses it" do
    edit_metric_via_form(instruction: "v2 instruction")
    draft = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id).order(:created_at).last
    draft.update!(instruction: "the version we actually want")

    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: draft.id }
    expect(metric.reload.instruction).to eq("the version we actually want")
  end

  it "publishes the specific draft passed in draft_id, not just the newest" do
    edit_metric_via_form(instruction: "first edit")
    older = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id).order(:created_at).last
    # A second edit replaces the prior edit-source draft (only one edit draft at a time).
    edit_metric_via_form(instruction: "second edit")
    second_draft = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "edit").order(:created_at).last
    expect(second_draft.id).not_to eq(older.id)

    # Publish the second (newer) edit draft.
    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: second_draft.id }
    expect(second_draft.reload.state).to eq("published")
  end

  it "flashes an alert when there is no draft to publish" do
    post "/completion_kit/metrics/#{metric.id}/publish_draft"
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
    follow_redirect!
    expect(response.body).to include("No version to publish")
  end

  it "replaces the prior edit-source draft instead of stacking when the user edits again" do
    edit_metric_via_form(instruction: "v2")
    first_count = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "edit").count
    edit_metric_via_form(instruction: "v3")
    second_count = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "edit").count
    expect(first_count).to eq(1)
    expect(second_count).to eq(1)
  end

  def suggestion_draft_with(summary)
    CompletionKit::MetricVersion.ensure_current_for(metric)
    CompletionKit::MetricVersion.create!(
      metric: metric, instruction: "v2 instruction", rubric_bands: metric.rubric_bands || [],
      state: "draft", source: "suggestion", current: false, validation_summary: summary
    )
  end

  it "renders the validation scoreboard for a suggestion draft that has a summary" do
    suggestion_draft_with({ "before" => 1, "after" => 4, "total" => 5, "tested" => 5, "fixes" => 3, "keeps" => 1, "breaks" => 1, "still_off" => 0, "capped" => false, "rows" => [] })
    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).to include("ck-scoreboard")
    expect(response.body).to include("Matches you on")
    expect(response.body).to include("4 of 5")
    expect(response.body).to include("Breaks")
  end

  it "warns when publishing a net-negative candidate" do
    suggestion_draft_with({ "before" => 3, "after" => 1, "total" => 5, "tested" => 5, "fixes" => 1, "keeps" => 0, "breaks" => 3, "still_off" => 1, "capped" => false, "rows" => [] })
    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).to include("Publish anyway?")
  end

  it "notes when the answer key was capped at 30" do
    suggestion_draft_with({ "before" => 10, "after" => 25, "total" => 30, "tested" => 30, "fixes" => 15, "keeps" => 10, "breaks" => 1, "still_off" => 4, "capped" => true, "rows" => [] })
    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).to include("Tested against your 30 most recent reviews")
  end
end

require "rails_helper"

RSpec.describe "CompletionKit metrics (judge suggest)", type: :request do
  let(:metric) { create(:completion_kit_metric) }
  let(:run) { create(:completion_kit_run) }
  let(:response_row) { create(:completion_kit_response, run: run) }

  def add_disagree(corrected: 3, note: "off")
    jv = CompletionKit::MetricVersion.ensure_current_for(metric)
    create(:completion_kit_calibration,
           run: run, response: response_row, metric: metric,
           metric_version: jv, verdict: "disagree",
           corrected_score: corrected, note: note, created_by: SecureRandom.uuid)
  end

  it "enqueues the suggestion job and shows a pending state on the metric page" do
    add_disagree
    expect {
      post "/completion_kit/metrics/#{metric.id}/suggest_variants", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to have_enqueued_job(CompletionKit::MetricSuggestionJob).with(metric.id)
    expect(response.body).to include("ck-suggestion-status-#{metric.id}")
    expect(response.body).to include("Drafting a change")
  end

  it "enqueues and redirects with a notice when posted from the edit page" do
    add_disagree
    expect {
      post "/completion_kit/metrics/#{metric.id}/suggest_variants", params: { back_to: "edit" }
    }.to have_enqueued_job(CompletionKit::MetricSuggestionJob).with(metric.id)
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}/edit")
    follow_redirect!
    expect(response.body).to include("Drafting a change")
  end

  it "still refuses when there are no disagreements" do
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    follow_redirect!
    expect(response.body).to include("Mark at least one case as Disagree")
  end

  it "shows no Suggest-improvements affordance when no disagreements exist (the calibration card guides toward verdicts instead)" do
    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).not_to include("Suggest improvements")
    expect(response.body).to include("Agreement")
  end

  it "enables the Suggest-improvements button as soon as a disagreement is collected" do
    add_disagree
    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).to include("Suggest improvements")
    expect(response.body).to match(%r{<form[^>]*action="/completion_kit/metrics/#{metric.id}/suggest_variants"})
  end

  it "offers a Suggest-improvements button on the edit page when disagreements exist and no draft is pending" do
    add_disagree
    get "/completion_kit/metrics/#{metric.id}/edit"
    expect(response.body).to include("Suggest improvements")
    expect(response.body).to match(%r{<form[^>]*action="/completion_kit/metrics/#{metric.id}/suggest_variants})
  end

  it "hides the edit-page Suggest-improvements button when no disagreements exist" do
    get "/completion_kit/metrics/#{metric.id}/edit"
    expect(response.body).not_to include("Suggest improvements")
  end

  def create_suggestion_draft(instruction: "be sharper", rubric_bands: nil)
    jv = CompletionKit::MetricVersion.ensure_current_for(metric)
    CompletionKit::MetricVersion.create!(
      metric: metric,
      instruction: instruction,
      rubric_bands: rubric_bands || metric.rubric_bands,
      state: "draft",
      source: "suggestion",
      current: false
    )
  end

  it "renders inline rubric band suggestions on the edit form when the draft changes a band" do
    add_disagree
    new_bands = [
      { "stars" => 5, "description" => "pristine and fully verifiable" },
      { "stars" => 4, "description" => "one minor lapse, no harm" },
      { "stars" => 3, "description" => "a couple of soft claims" },
      { "stars" => 2, "description" => "meaningful inaccuracies" },
      { "stars" => 1, "description" => "dangerously wrong" }
    ]
    create_suggestion_draft(instruction: "same instruction", rubric_bands: new_bands)
    get "/completion_kit/metrics/#{metric.id}/edit"
    expect(response.body).to include("Suggested band")
    expect(response.body).to include("Use this band")
    expect(response.body).to include("pristine and fully verifiable")
    expect(response.body).to include('data-target="metric[rubric_bands][0][description]"')
  end

  it "dismisses the inline suggestion via the dedicated route" do
    add_disagree
    draft = create_suggestion_draft

    delete "/completion_kit/metrics/#{metric.id}/dismiss_suggestion", params: { draft_id: draft.id }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
    expect(CompletionKit::MetricVersion.where(id: draft.id)).to be_empty
  end

  it "tolerates a dismiss request for a missing draft (no-op)" do
    delete "/completion_kit/metrics/#{metric.id}/dismiss_suggestion", params: { draft_id: 999_999 }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
  end

  it "routes the no-disagreement alert back to edit when back_to=edit" do
    post "/completion_kit/metrics/#{metric.id}/suggest_variants", params: { back_to: "edit" }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}/edit")
  end

  it "redirects back to edit when dismiss_suggestion is called with back_to=edit" do
    add_disagree
    draft = create_suggestion_draft

    delete "/completion_kit/metrics/#{metric.id}/dismiss_suggestion",
           params: { draft_id: draft.id, back_to: "edit" }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}/edit")
  end
end

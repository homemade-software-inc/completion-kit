require "rails_helper"

RSpec.describe "CompletionKit metrics (judge suggest)", type: :request do
  let(:metric) { create(:completion_kit_metric) }
  let(:run) { create(:completion_kit_run) }
  let(:response_row) { create(:completion_kit_response, run: run) }

  def stub_llm(text)
    client = instance_double("CompletionKit::OpenAiClient")
    allow(client).to receive(:generate_completion).and_return(text)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
  end

  def add_disagree(corrected: 3, note: "off")
    jv = CompletionKit::MetricVersion.ensure_current_for(metric)
    create(:completion_kit_calibration,
           run: run, response: response_row, metric: metric,
           metric_version: jv, verdict: "disagree",
           corrected_score: corrected, note: note, created_by: SecureRandom.uuid)
  end

  it "drafts a single new suggestion and redirects back to the metric page" do
    add_disagree
    stub_llm("VARIANT:\nREASONING: tighter\nINSTRUCTION:\nbe sharper\nEND_VARIANT")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
    follow_redirect!
    expect(response.body).to include("Drafted v")
    expect(response.body).to include("waiting in the Versions table above")
    expect(response.body).not_to include('value="Improve the metric"')
    expect(CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "suggestion").count).to eq(1)

    get "/completion_kit/metrics/#{metric.id}/edit"
    expect(response.body).to include("Proposed improvements")
    expect(response.body).to include("Apply all")
    expect(response.body).to include('aria-label="Discard"')
    expect(response.body).to include('aria-label="Try again"')
    expect(response.body).to include("Suggested wording")
    expect(response.body).to include("Use this wording")
  end

  it "replaces an existing suggestion draft instead of stacking new ones" do
    add_disagree
    stub_llm("VARIANT:\nREASONING: a\nINSTRUCTION:\nfirst\nEND_VARIANT")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    stub_llm("VARIANT:\nREASONING: b\nINSTRUCTION:\nsecond\nEND_VARIANT")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    drafts = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "suggestion")
    expect(drafts.count).to eq(1)
    expect(drafts.first.instruction).to eq("second")
  end

  it "refuses to call the model when no disagreements exist yet" do
    expect(CompletionKit::LlmClient).not_to receive(:for_model)
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    follow_redirect!
    expect(response.body).to include("Mark at least one case as Disagree")
  end

  it "redirects with an alert when the model returns nothing usable" do
    add_disagree
    stub_llm("nothing parseable")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    follow_redirect!
    expect(response.body).to include("no usable variants")
  end

  it "shows no Suggest-improvements affordance when no disagreements exist (the calibration card guides toward verdicts instead)" do
    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).not_to include("Suggest improvements")
    expect(response.body).to include("Calibration")
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

  it "renders inline rubric band suggestions on the edit form when the draft changes a band" do
    add_disagree
    rubric_block = <<~R
      VARIANT:
      REASONING: rubric tighter
      INSTRUCTION:
      same instruction
      RUBRIC:
      5: pristine and fully verifiable
      4: one minor lapse, no harm
      3: a couple of soft claims
      2: meaningful inaccuracies
      1: dangerously wrong
      END_VARIANT
    R
    stub_llm(rubric_block)
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    get "/completion_kit/metrics/#{metric.id}/edit"
    expect(response.body).to include("Suggested band")
    expect(response.body).to include("Use this band")
    expect(response.body).to include("pristine and fully verifiable")
    expect(response.body).to include('data-target="metric[rubric_bands][0][description]"')
  end

  it "dismisses the inline suggestion via the dedicated route" do
    add_disagree
    stub_llm("VARIANT:\nREASONING: r\nINSTRUCTION:\ndoomed\nEND_VARIANT")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    draft = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "suggestion").first

    delete "/completion_kit/metrics/#{metric.id}/dismiss_suggestion", params: { draft_id: draft.id }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
    expect(CompletionKit::MetricVersion.where(id: draft.id)).to be_empty
  end

  it "tolerates a dismiss request for a missing draft (no-op)" do
    delete "/completion_kit/metrics/#{metric.id}/dismiss_suggestion", params: { draft_id: 999_999 }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
  end

  it "redirects back to edit when suggest_variants is called with back_to=edit" do
    add_disagree
    stub_llm("VARIANT:\nREASONING: r\nINSTRUCTION:\nnext\nEND_VARIANT")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants", params: { back_to: "edit" }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}/edit")
  end

  it "still routes the no-disagreement and empty-variant alerts back to edit when back_to=edit" do
    post "/completion_kit/metrics/#{metric.id}/suggest_variants", params: { back_to: "edit" }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}/edit")

    add_disagree
    stub_llm("nothing parseable")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants", params: { back_to: "edit" }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}/edit")
  end

  it "redirects back to edit when dismiss_suggestion is called with back_to=edit" do
    add_disagree
    stub_llm("VARIANT:\nREASONING: r\nINSTRUCTION:\ndoomed\nEND_VARIANT")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    draft = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "suggestion").first

    delete "/completion_kit/metrics/#{metric.id}/dismiss_suggestion",
           params: { draft_id: draft.id, back_to: "edit" }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}/edit")
  end
end

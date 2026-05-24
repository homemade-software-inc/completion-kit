require "rails_helper"

RSpec.describe "CompletionKit metrics (judge suggest)", type: :request do
  let(:metric) { create(:completion_kit_metric) }

  def stub_llm(text)
    client = instance_double("CompletionKit::OpenAiClient")
    allow(client).to receive(:generate_completion).and_return(text)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
  end

  it "redirects from suggest_variants straight to the dedicated improvements page" do
    stub_llm("VARIANT:\nREASONING: tighter\nINSTRUCTION:\nbe sharper\nEND_VARIANT\nVARIANT:\nREASONING: kinder\nINSTRUCTION:\nbe kinder\nEND_VARIANT")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}/improvements")
    follow_redirect!
    expect(response.body).to include("Suggested improvements")
    expect(response.body).to include("sharper")
    expect(response.body).to include("kinder")
    expect(response.body).to include("Option 1 of 2")
    expect(response.body).to include("Use this version")
    expect(response.body).to include("Dismiss")
  end

  it "redirects with an alert when the model returns nothing usable" do
    stub_llm("nothing parseable")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    follow_redirect!
    expect(response.body).to include("no usable variants")
  end

  it "shows the pending-suggestions banner on the metric show page when drafts exist" do
    stub_llm("VARIANT:\nREASONING: r\nINSTRUCTION:\nrewrite\nEND_VARIANT")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"

    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).to include("alternative")
    expect(response.body).to include("waiting")
    expect(response.body).to include("/completion_kit/metrics/#{metric.id}/improvements")
  end

  it "renders the empty state on the improvements page when no drafts exist" do
    get "/completion_kit/metrics/#{metric.id}/improvements"
    expect(response.body).to include("No pending suggestions")
  end

  it "dismisses a suggestion draft via the dedicated route" do
    stub_llm("VARIANT:\nREASONING: r\nINSTRUCTION:\ndoomed\nEND_VARIANT")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    draft = CompletionKit::JudgeVersion.drafts.where(metric_id: metric.id, source: "suggestion").first

    delete "/completion_kit/metrics/#{metric.id}/dismiss_suggestion", params: { draft_id: draft.id }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}/improvements")
    expect(CompletionKit::JudgeVersion.where(id: draft.id)).to be_empty
  end

  it "tolerates a dismiss request for a missing draft (no-op)" do
    delete "/completion_kit/metrics/#{metric.id}/dismiss_suggestion", params: { draft_id: 999_999 }
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}/improvements")
  end
end

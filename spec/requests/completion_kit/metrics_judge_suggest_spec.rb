require "rails_helper"

RSpec.describe "CompletionKit metrics (judge suggest)", type: :request do
  let(:metric) { create(:completion_kit_metric) }

  def stub_llm(text)
    client = instance_double("CompletionKit::OpenAiClient")
    allow(client).to receive(:generate_completion).and_return(text)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
  end

  it "creates drafts, redirects with a success flash, and shows them on the metric page" do
    stub_llm("VARIANT:\nREASONING: tighter\nINSTRUCTION:\nbe sharper\nEND_VARIANT\nVARIANT:\nREASONING: kinder\nINSTRUCTION:\nbe kinder\nEND_VARIANT")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
    follow_redirect!
    expect(response.body).to include("Wrote 2 alternatives for the judge instruction")
    expect(response.body).to include("Suggested rewrites")
    expect(response.body).to include("be sharper")
  end

  it "uses the singular noun when only one variant is generated" do
    stub_llm("VARIANT:\nREASONING: only\nINSTRUCTION:\nlonely\nEND_VARIANT")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    follow_redirect!
    expect(response.body).to include("Wrote 1 alternative for the judge instruction")
  end

  it "redirects with an alert when the model returns nothing usable" do
    stub_llm("nothing parseable")
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    follow_redirect!
    expect(response.body).to include("no usable variants")
  end
end

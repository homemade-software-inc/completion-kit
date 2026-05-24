require "rails_helper"

RSpec.describe "CompletionKit starter metrics", type: :request do
  let(:starters) { CompletionKit::StarterMetrics::ALL }

  describe "GET /metrics (index empty state)" do
    it "renders all five starter cards when the org has no metrics" do
      get "/completion_kit/metrics"
      expect(response.body).to include("Start with a ready-made rubric")
      starters.each { |s| expect(response.body).to include(s.name) }
    end

    it "hides the empty-state starter row when no starters remain (all dismissed)" do
      starters.each { |s| CompletionKit::StarterMetricDismissal.create!(starter_key: s.key) }
      get "/completion_kit/metrics"
      expect(response.body).not_to include("Start with a ready-made rubric")
      expect(response.body).to include("No metrics yet")
    end
  end

  describe "GET /metrics (index non-empty)" do
    before { create(:completion_kit_metric, name: "Existing metric") }

    it "renders the 'Add a starter metric' row at the bottom" do
      get "/completion_kit/metrics"
      expect(response.body).to include("Add a starter metric")
      starters.each { |s| expect(response.body).to include(s.name) }
    end

    it "hides a starter whose name has been adopted (matching metric exists)" do
      create(:completion_kit_metric, name: "Tone")
      get "/completion_kit/metrics"
      expect(response.body).not_to include(%(<h3 class="ck-starter-card__name"><a class="ck-link" href="/completion_kit/metrics/starters/tone">))
      expect(response.body).to include("Correctness")
    end

    it "hides the starter section entirely once every starter is adopted or dismissed" do
      starters.each { |s| CompletionKit::StarterMetricDismissal.create!(starter_key: s.key) }
      get "/completion_kit/metrics"
      expect(response.body).not_to include("Add a starter metric")
    end
  end

  describe "GET /metrics/starters/:key" do
    it "renders the preview with name, why-use-this, judge instruction, and rubric bands" do
      get "/completion_kit/metrics/starters/correctness"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Correctness")
      expect(response.body).to include("Why use this")
      expect(response.body).to include("Judge instruction")
      expect(response.body).to include("Every fact in the output checks out.")
      expect(response.body).to include("Add Correctness to my metrics")
      expect(response.body).to include("Cancel")
    end

    it "redirects with an alert when the key is unknown" do
      get "/completion_kit/metrics/starters/bogus"
      expect(response).to redirect_to("/completion_kit/metrics")
      follow_redirect!
      expect(response.body).to include("Unknown starter metric")
    end
  end

  describe "POST /metrics/starters/:key (adopt)" do
    it "creates a metric with the starter's name, instruction, and rubric and redirects to the show page" do
      post "/completion_kit/metrics/starters/correctness"
      metric = CompletionKit::Metric.find_by(name: "Correctness")
      expect(metric).to be_present
      expect(metric.instruction).to include("factually right")
      expect(metric.rubric_bands.first["description"]).to eq("Every fact in the output checks out.")
      expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
      follow_redirect!
      expect(response.body).to include("Added the")
      expect(response.body).to include("Correctness")
      expect(response.body).to include("starter")
    end

    it "refuses to adopt when a metric with the same name already exists" do
      create(:completion_kit_metric, name: "Conciseness")
      post "/completion_kit/metrics/starters/conciseness"
      expect(response).to redirect_to("/completion_kit/metrics")
      follow_redirect!
      expect(response.body).to include("already exists")
    end

    it "redirects with an alert for an unknown starter key" do
      post "/completion_kit/metrics/starters/bogus"
      expect(response).to redirect_to("/completion_kit/metrics")
      follow_redirect!
      expect(response.body).to include("Unknown starter metric")
    end
  end

  describe "POST /metrics/starters/:key/dismiss" do
    it "records the dismissal and removes the card from the index" do
      expect {
        post "/completion_kit/metrics/starters/tone/dismiss"
      }.to change(CompletionKit::StarterMetricDismissal, :count).by(1)
      expect(response).to redirect_to("/completion_kit/metrics")
      follow_redirect!
      expect(response.body).to include("Dismissed")
      expect(response.body).to include("Tone")

      get "/completion_kit/metrics"
      expect(response.body).not_to include("/completion_kit/metrics/starters/tone\"")
    end

    it "is idempotent — dismissing twice doesn't error or create a duplicate" do
      post "/completion_kit/metrics/starters/tone/dismiss"
      expect {
        post "/completion_kit/metrics/starters/tone/dismiss"
      }.not_to change(CompletionKit::StarterMetricDismissal, :count)
    end

    it "redirects with an alert for an unknown starter key" do
      post "/completion_kit/metrics/starters/bogus/dismiss"
      follow_redirect!
      expect(response.body).to include("Unknown starter metric")
    end
  end

  describe "StarterMetrics.find" do
    it "returns nil for unknown keys" do
      expect(CompletionKit::StarterMetrics.find("nope")).to be_nil
    end

    it "returns the starter struct for known keys" do
      expect(CompletionKit::StarterMetrics.find("tone").name).to eq("Tone")
    end
  end

  describe "StarterMetrics.adopted?" do
    it "is true when a metric exists matching the starter's name" do
      starter = CompletionKit::StarterMetrics.find("tone")
      create(:completion_kit_metric, name: "Tone")
      expect(CompletionKit::StarterMetrics.adopted?(starter)).to be(true)
    end

    it "is false when no such metric exists" do
      starter = CompletionKit::StarterMetrics.find("tone")
      expect(CompletionKit::StarterMetrics.adopted?(starter)).to be(false)
    end
  end
end

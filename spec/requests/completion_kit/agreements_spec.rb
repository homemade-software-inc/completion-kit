require "rails_helper"

RSpec.describe "CompletionKit agreements (web)", type: :request do
  let(:metric) { create(:completion_kit_metric) }
  let(:prompt) { create(:completion_kit_prompt) }
  let(:run) { create(:completion_kit_run, prompt: prompt) }
  let(:response_row) { create(:completion_kit_response, run: run) }
  let!(:review) { create(:completion_kit_review, response: response_row, metric: metric, metric_name: metric.name, ai_score: 4.0, ai_feedback: "looks good") }

  def base_path
    "/completion_kit/runs/#{run.id}/responses/#{response_row.id}/agreements"
  end

  it "renders verdict buttons under each scored review on the response page" do
    get "/completion_kit/runs/#{run.id}/responses/#{response_row.id}"
    expect(response.body).to include("Your verdict")
    expect(response.body).to include("agree")
    expect(response.body).to include("disagree")
    expect(response.body).to include("borderline")
  end

  it "creates an agree agreement via the web endpoint" do
    post base_path, params: { metric_id: metric.id, verdict: "agree" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    expect(CompletionKit::Agreement.count).to eq(1)
    expect(CompletionKit::Agreement.first.verdict).to eq("agree")
  end

  it "flashes the Save button green (ck-button--just-saved) after a successful disagree save" do
    post base_path, params: { metric_id: metric.id, verdict: "disagree", corrected_score: 2, note: "off" },
                     headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.body).to include("ck-button--just-saved")
  end

  it "does not flash the Save button on the pending-verdict render (no save happened)" do
    post base_path, params: { metric_id: metric.id, verdict: "disagree" },
                     headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.body).not_to include("ck-button--just-saved")
  end

  it "does not flash the Save button when validation fails" do
    post base_path, params: { metric_id: metric.id, verdict: "disagree", corrected_score: 9 },
                     headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.body).not_to include("ck-button--just-saved")
  end

  it "upserts the same user's verdict on a repeat POST" do
    post base_path, params: { metric_id: metric.id, verdict: "agree" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    post base_path, params: { metric_id: metric.id, verdict: "borderline", note: "rubric ambiguous" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(CompletionKit::Agreement.count).to eq(1)
    cal = CompletionKit::Agreement.first
    expect(cal.verdict).to eq("borderline")
    expect(cal.note).to eq("rubric ambiguous")
  end

  it "renders the star picker + note inputs after a disagree verdict is saved" do
    post base_path, params: { metric_id: metric.id, verdict: "disagree", corrected_score: 2, note: "off" },
                     headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('class="ck-star-picker"')
    expect(response.body).to include('name="corrected_score"')
  end

  it "renders just the note field after a borderline verdict is saved" do
    post base_path, params: { metric_id: metric.id, verdict: "borderline" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.body).to include('placeholder="What made this borderline?')
    expect(response.body).not_to include('class="ck-star-picker"')
  end

  it "shows the others' verdict counter and a 'What others said' disclosure when a different operator has verdicted this row" do
    CompletionKit.config.current_reviewer = ->(_controller) { "alice" }
    post base_path, params: { metric_id: metric.id, verdict: "disagree", corrected_score: 2.0, note: "off by one" },
                     headers: { "Accept" => "text/vnd.turbo-stream.html" }
    CompletionKit.config.current_reviewer = nil
    get "/completion_kit/runs/#{run.id}/responses/#{response_row.id}"
    expect(response.body).to include("1 other verdict")
    expect(response.body).to include("on this score")
    expect(response.body).to include("What others said")
    expect(response.body).to include("alice")
    expect(response.body).to include("off by one")
  end

  it "does not show an others-counter when the only verdict on this row is the current operator's own" do
    post base_path, params: { metric_id: metric.id, verdict: "agree" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    get "/completion_kit/runs/#{run.id}/responses/#{response_row.id}"
    expect(response.body).not_to include("other verdict")
    expect(response.body).not_to include("What others said")
  end

  describe "reviewer identity" do
    def response_page
      "/completion_kit/runs/#{run.id}/responses/#{response_row.id}"
    end

    def stream_headers(extra = {})
      { "Accept" => "text/vnd.turbo-stream.html" }.merge(extra)
    end

    it "ignores an X-Remote-User header when no reviewer is configured" do
      post base_path, params: { metric_id: metric.id, verdict: "agree" },
                       headers: stream_headers("HTTP_X_REMOTE_USER" => "alice")
      expect(CompletionKit::Agreement.pluck(:created_by)).to eq(["operator"])
    end

    it "keeps a separate verdict for each reviewer that current_reviewer names" do
      CompletionKit.config.current_reviewer = ->(controller) { controller.request.headers["X-Remote-User"] }
      post base_path, params: { metric_id: metric.id, verdict: "agree" },
                       headers: stream_headers("HTTP_X_REMOTE_USER" => "alice")
      post base_path, params: { metric_id: metric.id, verdict: "disagree", corrected_score: 2.0 },
                       headers: stream_headers("HTTP_X_REMOTE_USER" => "bob")
      expect(CompletionKit::Agreement.pluck(:created_by, :verdict)).to contain_exactly(["alice", "agree"], ["bob", "disagree"])
    end

    it "stringifies whatever current_reviewer returns" do
      CompletionKit.config.current_reviewer = ->(_controller) { 42 }
      post base_path, params: { metric_id: metric.id, verdict: "agree" }, headers: stream_headers
      expect(CompletionKit::Agreement.pluck(:created_by)).to eq(["42"])
    end

    context "when current_reviewer returns nothing" do
      after { CompletionKit.instance_variable_set(:@config, nil) }

      it "falls back to the configured username" do
        CompletionKit.configure do |c|
          c.username = "admin"
          c.password = "secret"
          c.auth_strategy = ->(_controller) {}
          c.current_reviewer = ->(_controller) { "" }
        end
        post base_path, params: { metric_id: metric.id, verdict: "agree" }, headers: stream_headers
        expect(CompletionKit::Agreement.pluck(:created_by)).to eq(["admin"])
      end
    end

    it "marks the reviewer's own verdict active in the save response and lists only other reviewers" do
      create(:completion_kit_agreement, run: run, response: response_row, metric: metric,
             verdict: "borderline", created_by: "operator")
      CompletionKit.config.current_reviewer = ->(_controller) { "alice" }

      post base_path, params: { metric_id: metric.id, verdict: "agree" }, headers: stream_headers

      expect(response.body).to include("ck-agreement__pill--agree is-active")
      expect(response.body).to include("What others said (1)")
      expect(response.body).to include('<span class="ck-agreement__others-by">operator</span>')
      expect(response.body).not_to include('<span class="ck-agreement__others-by">alice</span>')
    end

    it "marks the reviewer's own verdict active after a reload instead of an older verdict under the default name" do
      create(:completion_kit_agreement, run: run, response: response_row, metric: metric,
             verdict: "disagree", corrected_score: 2.0, created_by: "operator")
      create(:completion_kit_agreement, run: run, response: response_row, metric: metric,
             verdict: "agree", created_by: "alice")
      CompletionKit.config.current_reviewer = ->(_controller) { "alice" }

      get response_page

      expect(response.body).to include("ck-agreement__pill--agree is-active")
      expect(response.body).not_to include("ck-agreement__pill--disagree is-active")
      expect(response.body).to include("What others said (1)")
      expect(response.body).to include('<span class="ck-agreement__others-by">operator</span>')
      expect(response.body).not_to include('<span class="ck-agreement__others-by">alice</span>')
    end
  end

  it "reveals the score form inline (no save, no flash) when disagree is clicked without a corrected_score" do
    post base_path, params: { metric_id: metric.id, verdict: "disagree" },
                     headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    expect(CompletionKit::Agreement.count).to eq(0)
    expect(response.body).to include("What should the score have been?")
    expect(response.body).to include('class="ck-star-picker"')
    expect(response.body).to include('name="corrected_score"')
    expect(response.body).to include('aria-pressed="true"')
  end

  it "renders the inline error inside the agreement block when a save genuinely fails" do
    post base_path, params: { metric_id: metric.id, verdict: "disagree", corrected_score: 9.0 },
                     headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("must be between 1 and 5")
    expect(response.body).to include('class="ck-agreement__error"')
    expect(CompletionKit::Agreement.count).to eq(0)
  end

  it "returns 404 when the judge_agreement_enabled flag is off" do
    original = CompletionKit.config.judge_agreement_enabled
    CompletionKit.config.judge_agreement_enabled = false
    post base_path, params: { metric_id: metric.id, verdict: "agree" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:not_found)
    expect(CompletionKit::Agreement.count).to eq(0)
  ensure
    CompletionKit.config.judge_agreement_enabled = original
  end

  it "hides the verdict buttons on the response page when the flag is off" do
    original = CompletionKit.config.judge_agreement_enabled
    CompletionKit.config.judge_agreement_enabled = false
    get "/completion_kit/runs/#{run.id}/responses/#{response_row.id}"
    expect(response.body).not_to include("Your verdict")
  ensure
    CompletionKit.config.judge_agreement_enabled = original
  end

  describe "check metrics" do
    let(:check_metric) { create(:completion_kit_metric, :check) }

    it "never renders agreement buttons for a check review even when a score and pass are present" do
      create(:completion_kit_review, :check, response: response_row, metric: check_metric,
             metric_name: check_metric.name,
             metric_version: CompletionKit::MetricVersion.ensure_current_for(check_metric),
             ai_score: 3.0, passed: true)

      get "/completion_kit/runs/#{run.id}/responses/#{response_row.id}"

      expect(response.body).to include(check_metric.name)
      expect(response.body).not_to include("agreement_#{response_row.id}_#{check_metric.id}")
    end

    it "refuses to create an agreement for a check metric with 422" do
      expect {
        post "/completion_kit/runs/#{run.id}/responses/#{response_row.id}/agreements",
             params: { metric_id: check_metric.id, verdict: "agree" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.not_to change(CompletionKit::Agreement, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end

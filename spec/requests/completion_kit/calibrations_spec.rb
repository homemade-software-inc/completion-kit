require "rails_helper"

RSpec.describe "CompletionKit calibrations (web)", type: :request do
  let(:metric) { create(:completion_kit_metric) }
  let(:prompt) { create(:completion_kit_prompt) }
  let(:run) { create(:completion_kit_run, prompt: prompt) }
  let(:response_row) { create(:completion_kit_response, run: run) }
  let!(:review) { create(:completion_kit_review, response: response_row, metric: metric, metric_name: metric.name, ai_score: 4.0, ai_feedback: "looks good") }

  def base_path
    "/completion_kit/runs/#{run.id}/responses/#{response_row.id}/calibrations"
  end

  it "renders verdict buttons under each scored review on the response page" do
    get "/completion_kit/runs/#{run.id}/responses/#{response_row.id}"
    expect(response.body).to include("Your verdict")
    expect(response.body).to include("agree")
    expect(response.body).to include("disagree")
    expect(response.body).to include("borderline")
  end

  it "creates an agree calibration via the web endpoint" do
    post base_path, params: { metric_id: metric.id, verdict: "agree" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    expect(CompletionKit::Calibration.count).to eq(1)
    expect(CompletionKit::Calibration.first.verdict).to eq("agree")
  end

  it "upserts the same user's verdict on a repeat POST" do
    post base_path, params: { metric_id: metric.id, verdict: "agree" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    post base_path, params: { metric_id: metric.id, verdict: "borderline", note: "rubric ambiguous" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(CompletionKit::Calibration.count).to eq(1)
    cal = CompletionKit::Calibration.first
    expect(cal.verdict).to eq("borderline")
    expect(cal.note).to eq("rubric ambiguous")
  end

  it "renders the slider + note inputs after a disagree verdict is saved" do
    post base_path, params: { metric_id: metric.id, verdict: "disagree", corrected_score: 2.5, note: "off" },
                     headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('type="range"')
    expect(response.body).to include('name="corrected_score"')
  end

  it "renders just the note field after a borderline verdict is saved" do
    post base_path, params: { metric_id: metric.id, verdict: "borderline" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.body).to include('placeholder="What made this borderline?')
    expect(response.body).not_to include('type="range"')
  end

  it "shows the verdict counter after at least one verdict is collected" do
    post base_path, params: { metric_id: metric.id, verdict: "agree" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    get "/completion_kit/runs/#{run.id}/responses/#{response_row.id}"
    expect(response.body).to include("1 verdict")
    expect(response.body).to include("on this score")
  end

  it "honors a remote-user header so different operators get their own row" do
    post base_path, params: { metric_id: metric.id, verdict: "agree" },
                     headers: { "Accept" => "text/vnd.turbo-stream.html", "HTTP_X_REMOTE_USER" => "alice" }
    post base_path, params: { metric_id: metric.id, verdict: "disagree", corrected_score: 2.0 },
                     headers: { "Accept" => "text/vnd.turbo-stream.html", "HTTP_X_REMOTE_USER" => "bob" }
    expect(CompletionKit::Calibration.count).to eq(2)
    expect(CompletionKit::Calibration.pluck(:created_by)).to contain_exactly("alice", "bob")
  end

  it "reveals the score form inline (no save, no flash) when disagree is clicked without a corrected_score" do
    post base_path, params: { metric_id: metric.id, verdict: "disagree" },
                     headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    expect(CompletionKit::Calibration.count).to eq(0)
    expect(response.body).to include("What should the score have been?")
    expect(response.body).to include('type="range"')
    expect(response.body).to include('name="corrected_score"')
    expect(response.body).to include('aria-pressed="true"')
  end

  it "renders the inline error inside the calibration block when a save genuinely fails" do
    post base_path, params: { metric_id: metric.id, verdict: "disagree", corrected_score: 9.0 },
                     headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("must be between 1 and 5")
    expect(response.body).to include('class="ck-calibration__error"')
    expect(CompletionKit::Calibration.count).to eq(0)
  end

  it "returns 404 when the judge_calibration_enabled flag is off" do
    original = CompletionKit.config.judge_calibration_enabled
    CompletionKit.config.judge_calibration_enabled = false
    post base_path, params: { metric_id: metric.id, verdict: "agree" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:not_found)
    expect(CompletionKit::Calibration.count).to eq(0)
  ensure
    CompletionKit.config.judge_calibration_enabled = original
  end

  it "hides the verdict buttons on the response page when the flag is off" do
    original = CompletionKit.config.judge_calibration_enabled
    CompletionKit.config.judge_calibration_enabled = false
    get "/completion_kit/runs/#{run.id}/responses/#{response_row.id}"
    expect(response.body).not_to include("Your verdict")
  ensure
    CompletionKit.config.judge_calibration_enabled = original
  end
end

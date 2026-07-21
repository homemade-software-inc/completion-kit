require "rails_helper"

RSpec.describe "CompletionKit runs", type: :request do
  let!(:prompt) { create(:completion_kit_prompt, name: "Prompt A", template: "Static prompt without variables") }
  let(:base_path) { "/completion_kit/runs" }

  it "renders index, show, new, and edit pages" do
    run = create(:completion_kit_run, prompt: prompt, name: "Run A")

    get base_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Run A")

    get "#{base_path}/#{run.id}"
    expect(response).to have_http_status(:ok)

    get "#{base_path}/new", params: { prompt_id: prompt.id }
    expect(response).to have_http_status(:ok)

    get "#{base_path}/#{run.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Run A")
  end

  it "shows a hidden-runs message, not the new-user CTA, when every run is hidden by the display scope" do
    create(:completion_kit_run, prompt: prompt, name: "Old Run", created_at: 90.days.ago)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    get base_path

    expect(response.body).not_to include("Create your first run")
    expect(response.body).to include("Your older runs are hidden")
  ensure
    CompletionKit.config.runs_display_scope = nil
  end

  it "still shows the new-user empty state for a genuinely empty workspace" do
    get base_path

    expect(response.body).to include("No runs yet")
    expect(response.body).to include("Create your first run")
  end

  it "filters the index list through a host-configured runs_display_scope" do
    create(:completion_kit_run, prompt: prompt, name: "Recent Run")
    create(:completion_kit_run, prompt: prompt, name: "Old Run", created_at: 90.days.ago)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    get base_path

    expect(response.body).to include("Recent Run")
    expect(response.body).not_to include("Old Run")
  ensure
    CompletionKit.config.runs_display_scope = nil
  end

  it "passes the shown (post-scope) runs to the host-configured runs_display_footer_partial as a local" do
    create(:completion_kit_run, prompt: prompt, name: "Recent A")
    create(:completion_kit_run, prompt: prompt, name: "Recent B")
    create(:completion_kit_run, prompt: prompt, name: "Old Run", created_at: 90.days.ago)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }
    CompletionKit.config.runs_display_footer_partial = "spec_host/runs_footer"

    get base_path

    expect(response.body).to include("spec-host-runs-footer: 2 runs in view")
  ensure
    CompletionKit.config.runs_display_footer_partial = nil
    CompletionKit.config.runs_display_scope = nil
  end

  it "excludes runs hidden by runs_display_scope from the compare picker" do
    dataset = create(:completion_kit_dataset)
    anchor = create(:completion_kit_run, prompt: prompt, dataset: dataset, status: "completed")
    create(:completion_kit_run, prompt: prompt, dataset: dataset, name: "Old Candidate", created_at: 90.days.ago, status: "completed")
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    get "#{base_path}/#{anchor.id}/compare"

    expect(response.body).not_to include("Old Candidate")
  ensure
    CompletionKit.config.runs_display_scope = nil
  end

  it "renders Pass/Fail and a Broke badge for a check that regressed across runs" do
    dataset = create(:completion_kit_dataset, csv_data: "input\nhi\n")
    left = create(:completion_kit_run, prompt: prompt, dataset: dataset, status: "completed")
    right = create(:completion_kit_run, prompt: prompt, dataset: dataset, status: "completed")
    check = create(:completion_kit_metric, :check)
    v1 = CompletionKit::MetricVersion.ensure_current_for(check)
    left_response = create(:completion_kit_response, run: left, input_data: "hi", response_text: '{"ok":1}')
    right_response = create(:completion_kit_response, run: right, input_data: "hi", response_text: "not json")
    create(:completion_kit_review, :check, response: left_response, metric: check, metric_name: check.name, metric_version_id: v1.id, passed: true)
    create(:completion_kit_review, :check, response: right_response, metric: check, metric_name: check.name, metric_version_id: v1.id, passed: false)

    get "#{base_path}/#{left.id}/compare", params: { with: right.id }

    expect(response.body).to include("Pass")
    expect(response.body).to include("Fail")
    expect(response.body).to include("Broke")
  end

  it "renders placeholders for a one-sided check row in compare" do
    dataset = create(:completion_kit_dataset, csv_data: "input\nhi\n")
    left = create(:completion_kit_run, prompt: prompt, dataset: dataset, status: "completed")
    right = create(:completion_kit_run, prompt: prompt, dataset: dataset, status: "completed")
    check = create(:completion_kit_metric, :check)
    v1 = CompletionKit::MetricVersion.ensure_current_for(check)
    left_response = create(:completion_kit_response, run: left, input_data: "hi", response_text: "x")
    create(:completion_kit_response, run: right, input_data: "hi", response_text: "y")
    create(:completion_kit_review, :check, response: left_response, metric: check, metric_name: check.name, metric_version_id: v1.id, passed: true)

    get "#{base_path}/#{left.id}/compare", params: { with: right.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pass")
  end

  it "does not seed new-run tags from a run hidden by runs_display_scope" do
    create(:completion_kit_run, prompt: prompt, created_at: 90.days.ago, tag_names: ["stale"])
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    get "#{base_path}/new", params: { prompt_id: prompt.id }

    expect(response.body).not_to match(/value="stale"[^>]*\bchecked\b/)
  ensure
    CompletionKit.config.runs_display_scope = nil
  end

  it "renders the new-run form with no prompt preselected" do
    get "#{base_path}/new"
    expect(response).to have_http_status(:ok)
  end

  it "surfaces the answer-key column field and marks metrics that grade against expected" do
    create(:completion_kit_metric, :check, name: "VIN match",
      check_config: { "check_kind" => "equals", "target" => "response_text", "compare_to" => "expected" })
    create(:completion_kit_metric, name: "Helpfulness")

    get "#{base_path}/new"

    expect(response.body).to include('id="run_expected_column"')
    expect(response.body).to include("Answer-key column")
    expect(response.body).to include('data-compare-expected="1"')
    expect(response.body).to include('data-compare-expected="0"')
  end

  it "skips the empty metrics-hint placeholder when there are no metrics" do
    get "#{base_path}/new"
    expect(response.body).not_to include('id="metrics-hint"')
    expect(response.body).to include("No metrics yet")
  end

  it "still renders the metrics-hint placeholder when there are metrics (the JS populates it)" do
    create(:completion_kit_metric)
    get "#{base_path}/new"
    expect(response.body).to include('id="metrics-hint"')
  end

  it "renders the new-run form when the prompt has no prior runs" do
    fresh = create(:completion_kit_prompt, name: "Untouched Prompt")
    get "#{base_path}/new", params: { prompt_id: fresh.id }
    expect(response).to have_http_status(:ok)
  end

  it "inherits tags from the most recent run of the prompt family on the new-run form" do
    create(:completion_kit_run, prompt: prompt, tag_names: ["real estate", "priority"])

    get "#{base_path}/new", params: { prompt_id: prompt.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/<input(?=[^>]*name="run\[tag_names\]\[\]")(?=[^>]*value="real estate")(?=[^>]*\bchecked\b)/)
    expect(response.body).to match(/<input(?=[^>]*name="run\[tag_names\]\[\]")(?=[^>]*value="priority")(?=[^>]*\bchecked\b)/)
  end

  it "paginates the responses table for a large (gradable) run and clamps out-of-range pages" do
    run = create(:completion_kit_run, prompt: prompt, name: "Big Run", status: "completed")
    now = Time.current
    attrs = (0...101).map { |i| { run_id: run.id, status: "succeeded", row_index: i, response_text: "row #{i}", attempts: 0, created_at: now, updated_at: now } }
    CompletionKit::Response.insert_all(attrs)
    allow_any_instance_of(CompletionKit::Run).to receive(:gradable?).and_return(true)

    get "#{base_path}/#{run.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Page 1 of 2")
    expect(response.body).to include("101 responses")

    get "#{base_path}/#{run.id}", params: { page: 2 }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Page 2 of 2")

    get "#{base_path}/#{run.id}", params: { page: 999 }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Page 2 of 2")

    get "#{base_path}/#{run.id}", params: { page: ["1"] }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Page 1 of 2")
  end

  it "renders the responses table without a per-row query (no N+1 on fully_reviewed?)" do
    metric = create(:completion_kit_metric)
    build_run = ->(row_count) do
      run = create(:completion_kit_run, prompt: prompt, status: "completed")
      run.replace_metrics!([metric.id])
      row_count.times do |i|
        resp = create(:completion_kit_response, run: run, status: "succeeded", row_index: i, response_text: "body #{i}")
        create(:completion_kit_review, response: resp, metric: metric, metric_name: "Quality", status: "succeeded", ai_score: 4.0)
      end
      run
    end
    small = build_run.call(2)
    large = build_run.call(8)

    query_count = ->(run) do
      count = 0
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        payload = ActiveSupport::Notifications::Event.new(*args).payload
        count += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/) || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/i)
      end
      get "#{base_path}/#{run.id}"
      ActiveSupport::Notifications.unsubscribe(sub)
      count
    end

    large_count = query_count.call(large)
    small_count = query_count.call(small)
    expect(response).to have_http_status(:ok)
    expect(large_count).to eq(small_count)
  end

  it "sorts responses by rubric score when the run is gradable" do
    run = create(:completion_kit_run, prompt: prompt, name: "Run A")
    r1 = create(:completion_kit_response, run: run)
    r2 = create(:completion_kit_response, run: run)
    create(:completion_kit_review, response: r1, ai_score: 4.0)
    create(:completion_kit_review, response: r2, ai_score: 2.0)

    allow_any_instance_of(CompletionKit::Run).to receive(:gradable?).and_return(true)

    get "#{base_path}/#{run.id}", params: { sort: "score_asc" }
    expect(response).to have_http_status(:ok)

    get "#{base_path}/#{run.id}", params: { sort: "score_desc" }
    expect(response).to have_http_status(:ok)
  end

  it "surfaces responses with failed checks first in the composite worst-first order" do
    check = create(:completion_kit_metric, :check)
    run = create(:completion_kit_run, prompt: prompt, name: "Check run")
    run.replace_metrics!([check.id])
    clean = create(:completion_kit_response, run: run, response_text: "ok one")
    broken = create(:completion_kit_response, run: run, response_text: "ok two")
    create(:completion_kit_review, :check, response: clean, metric: check, metric_name: check.name, passed: true)
    create(:completion_kit_review, :check, response: broken, metric: check, metric_name: check.name, passed: false)

    get "#{base_path}/#{run.id}", params: { sort: "score_asc" }

    expect(response).to have_http_status(:ok)
    expect(response.body.index("response_#{broken.id}")).to be < response.body.index("response_#{clean.id}")
  end

  it "orders responses by id when the run is not gradable" do
    run = create(:completion_kit_run, prompt: prompt, name: "Run A")
    create(:completion_kit_response, run: run)

    allow_any_instance_of(CompletionKit::Run).to receive(:gradable?).and_return(false)

    get "#{base_path}/#{run.id}"
    expect(response).to have_http_status(:ok)
  end

  it "renders check pass-rate pips and a pass-rate badge on the index for a mixed run" do
    llm = create(:completion_kit_metric, name: "Quality")
    check = create(:completion_kit_metric, :check, name: "Valid JSON")
    run = create(:completion_kit_run, prompt: prompt, name: "Mixed index run")
    run.replace_metrics!([llm.id, check.id])
    resp = create(:completion_kit_response, run: run)
    create(:completion_kit_review, response: resp, metric: llm, metric_name: "Quality", ai_score: 4.0)
    create(:completion_kit_review, :check, response: resp, metric: check, metric_name: "Valid JSON", passed: true)

    get base_path

    expect(response.body).to include("Mixed index run")
    expect(response.body).to include("Valid JSON")
    expect(response.body).to include("100%")
  end

  it "renders only a pass-rate badge on the index for a check-only run" do
    check = create(:completion_kit_metric, :check, name: "JSON only")
    run = create(:completion_kit_run, prompt: prompt, name: "Checks only index")
    run.replace_metrics!([check.id])
    resp = create(:completion_kit_response, run: run)
    create(:completion_kit_review, :check, response: resp, metric: check, metric_name: "JSON only", passed: false)

    get base_path

    expect(response.body).to include("Checks only index")
    expect(response.body).to include("0%")
  end

  it "renders check pips, a pass-rate fraction, and grading cells on the run page for a mixed run" do
    llm = create(:completion_kit_metric, name: "Quality")
    check = create(:completion_kit_metric, :check, name: "Valid JSON")
    run = create(:completion_kit_run, prompt: prompt, name: "Mixed show", status: "completed", progress_total: 1)
    run.replace_metrics!([llm.id, check.id])
    resp = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
    create(:completion_kit_review, response: resp, metric: llm, metric_name: "Quality", ai_score: 4.0)
    create(:completion_kit_review, :check, response: resp, metric: check, metric_name: "Valid JSON", passed: true)

    get "#{base_path}/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pass")
    expect(response.body).to include("1/1")
    expect(response.body).to include(">Checks passed</p>")
    expect(response.body).to include(">Avg score</p>")
  end

  it "renders a Fail pip and a fraction on the run page for a failing check response" do
    check = create(:completion_kit_metric, :check, name: "Valid JSON")
    run = create(:completion_kit_run, prompt: prompt, name: "Failing show", status: "completed", progress_total: 1)
    run.replace_metrics!([check.id])
    resp = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
    create(:completion_kit_review, :check, response: resp, metric: check, metric_name: "Valid JSON", passed: false)

    get "#{base_path}/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Fail")
    expect(response.body).to include("0/1")
  end

  it "shows the judge avg cell and hides the checks cell on an llm-only run status panel" do
    llm = create(:completion_kit_metric, name: "Quality")
    run = create(:completion_kit_run, prompt: prompt, name: "LLM panel", status: "completed", progress_total: 1, judge_model: "gpt-4o")
    run.replace_metrics!([llm.id])
    resp = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
    create(:completion_kit_review, response: resp, metric: llm, metric_name: "Quality", ai_score: 4.0)

    get "#{base_path}/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(">Avg score</p>")
    expect(response.body).not_to include(">Checks passed</p>")
  end

  it "shows a pending pip, an em-dash checks cell, and no judge avg cell for a check-only run still grading" do
    check = create(:completion_kit_metric, :check, name: "Valid JSON")
    run = create(:completion_kit_run, prompt: prompt, name: "Checks grading", status: "running", progress_total: 1)
    run.replace_metrics!([check.id])
    resp = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
    create(:completion_kit_review, :check, response: resp, metric: check, metric_name: "Valid JSON", passed: nil, status: "pending")

    get "#{base_path}/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ck-metric-pip--pending")
    expect(response.body).to include(">Checks passed</p>")
    expect(response.body).not_to include(">Avg score</p>")
  end

  it "renders the show page with pending, retrying, and failed response rows" do
    run = create(:completion_kit_run, prompt: prompt, status: "running")
    create(:completion_kit_response, :pending, run: run)
    create(:completion_kit_response, :retrying, run: run)
    create(:completion_kit_response, :failed, run: run)

    get "#{base_path}/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Queued")
    expect(response.body).to include("Retrying")
    expect(response.body).to include("ck-chip--retry")
  end

  it "renders a failed response row with provider error details" do
    run = create(:completion_kit_run, prompt: prompt)
    create(:completion_kit_response, :failed, run: run, error_provider: "openai", error_status: 429, error_message: "Rate limit exceeded")

    get "#{base_path}/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Openai")
    expect(response.body).to include("429")
    expect(response.body).to include("Rate limit exceeded")
  end

  it "renders succeeded response with judging chip when run is still running and a judge is configured" do
    metric = create(:completion_kit_metric)
    run = create(:completion_kit_run, prompt: prompt, status: "running")
    run.replace_metrics!([metric.id])
    create(:completion_kit_response, run: run, status: "succeeded", response_text: "Output text")

    get "#{base_path}/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Judging")
  end

  it "renders Done chip on succeeded responses when the run has no judge configured" do
    run = create(:completion_kit_run, prompt: prompt, status: "completed")
    create(:completion_kit_response, run: run, status: "succeeded", response_text: "Output text")

    get "#{base_path}/#{run.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Done")
  end

  it "creates a run with valid params" do
    dataset = create(:completion_kit_dataset)

    expect do
      post base_path, params: { run: { prompt_id: prompt.id, dataset_id: dataset.id } }
    end.to change(CompletionKit::Run, :count).by(1)

    expect(response).to redirect_to(%r{/completion_kit/runs/\d+})
  end

  it "creates a judge-only run with no prompt and an output_column" do
    dataset = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")

    expect do
      post base_path, params: { run: { name: "Judge baseline", dataset_id: dataset.id, output_column: "actual_output" } }
    end.to change(CompletionKit::Run, :count).by(1)

    run = CompletionKit::Run.order(:id).last
    expect(run.prompt_id).to be_nil
    expect(run.output_column).to eq("actual_output")
    expect(run).to be_judge_only
  end

  it "persists an expected_column answer-key override from the form" do
    prompt = create(:completion_kit_prompt, template: "Static")
    dataset = create(:completion_kit_dataset, csv_data: "input,true_vin\nhi,X1\n")

    post base_path, params: { run: { name: "Ground truth", prompt_id: prompt.id, dataset_id: dataset.id, expected_column: "true_vin" } }

    expect(CompletionKit::Run.order(:id).last.expected_column).to eq("true_vin")
  end

  it "rejects a run whose expected_column is not a dataset column" do
    prompt = create(:completion_kit_prompt, template: "Static")
    dataset = create(:completion_kit_dataset, csv_data: "input,true_vin\nhi,X1\n")

    expect do
      post base_path, params: { run: { name: "Bad key", prompt_id: prompt.id, dataset_id: dataset.id, expected_column: "gold" } }
    end.not_to change(CompletionKit::Run, :count)
    expect(response.body).to include("is not a column")
  end

  it "rejects a judge-only run when the dataset lacks the output_column" do
    dataset = create(:completion_kit_dataset, csv_data: "input,response\nhi,hello\n")

    post base_path, params: { run: { name: "Bad column", dataset_id: dataset.id, output_column: "actual_output" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("is not a column on dataset")
  end

  it "creates a run with metric_ids" do
    metric = create(:completion_kit_metric)

    expect do
      post base_path, params: { run: { prompt_id: prompt.id, metric_ids: [metric.id] } }
    end.to change(CompletionKit::Run, :count).by(1)

    run = CompletionKit::Run.last
    expect(run.metric_ids).to eq([metric.id])
    expect(response).to redirect_to(%r{/completion_kit/runs/\d+})
  end

  it "renders new when create is invalid" do
    post base_path, params: { run: { prompt_id: nil } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("prevented this run from being saved")
  end

  it "updates a run with valid params" do
    run = create(:completion_kit_run, prompt: prompt, name: "Old Run")
    dataset = create(:completion_kit_dataset)

    patch "#{base_path}/#{run.id}", params: { run: { prompt_id: prompt.id, dataset_id: dataset.id } }

    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
  end

  it "updates a run with metric_ids" do
    run = create(:completion_kit_run, prompt: prompt)
    metric = create(:completion_kit_metric)

    patch "#{base_path}/#{run.id}", params: { run: { prompt_id: prompt.id, metric_ids: [metric.id] } }

    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
    expect(run.reload.metric_ids).to eq([metric.id])
  end

  it "updates a run with responses in place when only the name changes" do
    run = create(:completion_kit_run, prompt: prompt, name: "Original")
    run.responses.create!(response_text: "Some output")

    expect do
      patch "#{base_path}/#{run.id}", params: { run: { name: "Renamed", prompt_id: prompt.id } }
    end.not_to change(CompletionKit::Run, :count)

    expect(run.reload.name).to eq("Renamed")
    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
  end

  it "updates a run with responses in place when only the tags change" do
    run = create(:completion_kit_run, prompt: prompt)
    run.responses.create!(response_text: "Some output")

    expect do
      patch "#{base_path}/#{run.id}", params: { run: { prompt_id: prompt.id, tag_names: ["real estate"] } }
    end.not_to change(CompletionKit::Run, :count)

    expect(run.reload.tag_names).to eq(["real estate"])
    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
  end

  it "updates a run with responses in place when metrics are resubmitted unchanged" do
    metric = create(:completion_kit_metric)
    run = create(:completion_kit_run, prompt: prompt)
    run.replace_metrics!([metric.id])
    run.responses.create!(response_text: "Some output")

    expect do
      patch "#{base_path}/#{run.id}", params: { run: { name: "Renamed", prompt_id: prompt.id, metric_ids: [metric.id] } }
    end.not_to change(CompletionKit::Run, :count)

    expect(run.reload.name).to eq("Renamed")
  end

  it "forks a new run when the dataset changes on a run with responses" do
    run = create(:completion_kit_run, prompt: prompt, name: "Original")
    run.responses.create!(response_text: "Some output")
    new_dataset = create(:completion_kit_dataset)

    expect do
      patch "#{base_path}/#{run.id}", params: { run: { name: "Original", prompt_id: prompt.id, dataset_id: new_dataset.id } }
    end.to change(CompletionKit::Run, :count).by(1)

    new_run = CompletionKit::Run.order(:id).last
    expect(new_run.dataset_id).to eq(new_dataset.id)
    expect(new_run.status).to eq("pending")
    expect(new_run.name).not_to eq(run.name)
    expect(response).to redirect_to("/completion_kit/runs/#{new_run.id}")
    expect(run.reload.name).to eq("Original")
  end

  it "re-renders the edit form instead of 500ing when the fork has an invalid answer-key column" do
    static = create(:completion_kit_prompt, template: "Static")
    dataset = create(:completion_kit_dataset, csv_data: "input,true_vin\nhi,X1\n")
    run = create(:completion_kit_run, prompt: static, dataset: dataset, name: "Keep")
    run.responses.create!(response_text: "Some output")

    expect do
      patch "#{base_path}/#{run.id}", params: { run: { name: "Keep", prompt_id: static.id, dataset_id: dataset.id, expected_column: "gold" } }
    end.not_to change(CompletionKit::Run, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("is not a column")
  end

  it "forks a new run when the judge model changes on a run with responses" do
    run = create(:completion_kit_run, prompt: prompt)
    run.responses.create!(response_text: "Some output")

    expect do
      patch "#{base_path}/#{run.id}", params: { run: { name: "Original", prompt_id: prompt.id, judge_model: "claude-haiku-4-5" } }
    end.to change(CompletionKit::Run, :count).by(1)

    expect(CompletionKit::Run.order(:id).last.judge_model).to eq("claude-haiku-4-5")
  end

  it "forks a new run when the temperature changes on a run with responses" do
    run = create(:completion_kit_run, prompt: prompt, temperature: 1.0)
    run.responses.create!(response_text: "Some output")

    expect do
      patch "#{base_path}/#{run.id}", params: { run: { name: "Original", prompt_id: prompt.id, temperature: "0.3" } }
    end.to change(CompletionKit::Run, :count).by(1)

    expect(CompletionKit::Run.order(:id).last.temperature).to eq(0.3)
  end

  it "carries metric_ids onto the new run when updating a run with responses" do
    run = create(:completion_kit_run, prompt: prompt, name: "Original")
    run.responses.create!(response_text: "Some output")
    metric = create(:completion_kit_metric)

    patch "#{base_path}/#{run.id}", params: { run: { name: "Updated", prompt_id: prompt.id, metric_ids: [metric.id] } }

    new_run = CompletionKit::Run.order(:id).last
    expect(new_run.metric_ids).to eq([metric.id])
  end

  it "renders edit when update is invalid" do
    run = create(:completion_kit_run, prompt: prompt)

    allow_any_instance_of(CompletionKit::Run).to receive(:update) do |instance, _attrs|
      instance.errors.add(:base, "something went wrong")
      false
    end

    patch "#{base_path}/#{run.id}", params: { run: { prompt_id: prompt.id } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("prevented this run from being saved")
  end

  it "destroys a run" do
    run = create(:completion_kit_run, prompt: prompt)

    expect do
      delete "#{base_path}/#{run.id}"
    end.to change(CompletionKit::Run, :count).by(-1)

    expect(response).to redirect_to("/completion_kit/runs")
  end

  it "calls start! and redirects on success" do
    run = create(:completion_kit_run, prompt: prompt)
    expect_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(true)
    post "#{base_path}/#{run.id}/generate"
    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
  end

  it "redirects with alert when start! fails" do
    run = create(:completion_kit_run, prompt: prompt)
    allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(false)
    allow_any_instance_of(CompletionKit::Run).to receive(:failure_summary).and_return("Something went wrong")
    post "#{base_path}/#{run.id}/generate"
    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
    expect(flash[:alert]).to eq("Something went wrong")
  end

  it "rerun creates a new run with the same configuration and starts it" do
    metric = create(:completion_kit_metric)
    dataset = create(:completion_kit_dataset)
    source_run = create(:completion_kit_run, prompt: prompt, dataset: dataset, judge_model: "gpt-4.1", temperature: 0.3, status: "completed")
    source_run.replace_metrics!([metric.id])
    allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(true)

    expect { post "#{base_path}/#{source_run.id}/rerun" }
      .to change(CompletionKit::Run, :count).by(1)

    new_run = CompletionKit::Run.order(:id).last
    expect(new_run.id).not_to eq(source_run.id)
    expect(new_run.prompt_id).to eq(source_run.prompt_id)
    expect(new_run.dataset_id).to eq(source_run.dataset_id)
    expect(new_run.judge_model).to eq("gpt-4.1")
    expect(new_run.temperature).to eq(0.3)
    expect(new_run.metric_ids).to eq([metric.id])
    expect(response).to redirect_to("/completion_kit/runs/#{new_run.id}")
  end

  it "rerun carries over the source run's tags" do
    source_run = create(:completion_kit_run, prompt: prompt, status: "completed", tag_names: ["alpha", "beta"])
    allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(true)

    post "#{base_path}/#{source_run.id}/rerun"

    expect(CompletionKit::Run.order(:id).last.tag_names).to match_array(%w[alpha beta])
  end

  it "round-trips tag_names on create and update" do
    post "/completion_kit/runs", params: {
      run: { name: "R", prompt_id: prompt.id, tag_names: ["beta"] }
    }
    run = CompletionKit::Run.find_by!(name: "R")
    expect(run.tag_names).to eq(["beta"])

    patch "/completion_kit/runs/#{run.id}", params: {
      run: { tag_names: [] }
    }
    expect(run.reload.tag_names).to eq([])
  end

  it "rerun redirects with an alert when start! fails on the new run" do
    source_run = create(:completion_kit_run, prompt: prompt, status: "completed")
    allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(false)
    allow_any_instance_of(CompletionKit::Run).to receive(:failure_summary).and_return("config gone")

    post "#{base_path}/#{source_run.id}/rerun"
    new_run = CompletionKit::Run.order(:id).last
    expect(response).to redirect_to("/completion_kit/runs/#{new_run.id}")
    expect(flash[:alert]).to eq("config gone")
  end

  it "refresh_status returns a turbo stream replacing the run status header" do
    run = create(:completion_kit_run, prompt: prompt, status: "running")
    get "#{base_path}/#{run.id}/refresh_status", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("turbo-stream")
    expect(response.body).to include("run_status_header")
  end

  it "suggest action creates a pending suggestion, enqueues the validating job, and redirects" do
    run = create(:completion_kit_run, prompt: prompt)

    expect { post "#{base_path}/#{run.id}/suggest" }
      .to have_enqueued_job(CompletionKit::PromptSuggestionJob)
    suggestion = CompletionKit::Suggestion.order(:id).last
    expect(suggestion).to be_pending
    expect(suggestion.original_template).to eq(prompt.template)
    expect(response).to redirect_to("/completion_kit/suggestions/#{suggestion.id}?from=run")
  end

  it "suggest action redirects with an alert for a judge-only run" do
    judge_only = create(:completion_kit_run,
                        prompt: nil,
                        dataset: create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n"),
                        output_column: "actual_output")

    expect { post "#{base_path}/#{judge_only.id}/suggest" }.not_to change(CompletionKit::Suggestion, :count)
    expect(response).to redirect_to("/completion_kit/runs/#{judge_only.id}")
    expect(flash[:alert]).to include("scores existing outputs")
  end

  it "rerun copies output_column when re-running a judge-only run" do
    dataset = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")
    source_run = create(:completion_kit_run,
                        prompt: nil,
                        dataset: dataset,
                        output_column: "actual_output",
                        status: "completed")
    allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(true)

    post "#{base_path}/#{source_run.id}/rerun"

    new_run = CompletionKit::Run.order(:id).last
    expect(new_run.output_column).to eq("actual_output")
    expect(new_run.prompt_id).to be_nil
  end

  it "rerun copies expected_column onto the new run" do
    static = create(:completion_kit_prompt, template: "Static")
    dataset = create(:completion_kit_dataset, csv_data: "input,true_vin\nhi,X1\n")
    source_run = create(:completion_kit_run, prompt: static, dataset: dataset,
                        expected_column: "true_vin", status: "completed")
    allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(true)

    post "#{base_path}/#{source_run.id}/rerun"

    expect(CompletionKit::Run.order(:id).last.expected_column).to eq("true_vin")
  end

  it "filters runs by tag" do
    marine_run = create(:completion_kit_run, prompt: prompt, name: "Shark classifier run")
    real_estate_run = create(:completion_kit_run, prompt: prompt, name: "Property listing run")
    marine_run.update!(tag_names: ["marine biology"])
    real_estate_run.update!(tag_names: ["real estate"])

    get "/completion_kit/runs?tag[]=marine biology"
    expect(response.body).to include("Shark classifier run")
    expect(response.body).not_to include("Property listing run")

    get "/completion_kit/runs?tag[]=marine biology&tag[]=real estate"
    expect(response.body).to include("Shark classifier run")
    expect(response.body).to include("Property listing run")

    get "/completion_kit/runs"
    expect(response.body).to include("Shark classifier run")
    expect(response.body).to include("Property listing run")
  end

  it "renders no filter bar when no tags exist" do
    create(:completion_kit_run, prompt: prompt, name: "Basic run")
    get "/completion_kit/runs"
    expect(response.body).not_to include("Filter by tag")
  end

  it "shows the filter bar when tags exist" do
    CompletionKit::Tag.create!(name: "z")
    create(:completion_kit_run, prompt: prompt, name: "Basic run")
    get "/completion_kit/runs"
    expect(response.body).to include("Filter by tag")
  end

end

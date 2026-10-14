require "rails_helper"

RSpec.describe "Model ids no configured provider serves", type: :request do
  let(:token) { "test-api-token" }
  let(:api_headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }
  let(:api) { "/completion_kit/api/v1" }
  let(:llm_metric) { create(:completion_kit_metric) }
  let(:check_metric) { create(:completion_kit_metric, :check) }

  before do
    CompletionKit.config.api_token = token
    allow(CompletionKit::ModelDiscoveryJob).to receive(:perform_later)
    allow(CompletionKit::StartRunJob).to receive(:perform_later)
    allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
    allow(CompletionKit::JudgeReviewJob).to receive(:perform_later)
    allow(CompletionKit::CheckReviewJob).to receive(:perform_later)
    allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
    create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    create(:completion_kit_model, provider: "openai", model_id: "gpt-4.1-mini")
    create(:completion_kit_model, provider: "ollama", model_id: "llama3", status: "retired")
  end

  after { CompletionKit.instance_variable_set(:@config, nil) }

  def mcp_call(name, arguments)
    post "/completion_kit/mcp",
         params: {jsonrpc: "2.0", method: "tools/call", id: 1, params: {name: name, arguments: arguments}}.to_json,
         headers: api_headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).not_to have_key("error")
    body["result"]
  end

  def expect_tool_error(result, including:)
    expect(result["isError"]).to be(true)
    expect(result.dig("content", 0, "text")).to include(including)
  end

  def json_error
    JSON.parse(response.body)["error"]
  end

  %w[llama3 ollama/llama3].each do |unknown|
    context "with #{unknown.inspect}" do
      let(:unknown_model) { unknown }
      let(:model_message) { %(No configured provider serves model "#{unknown}") }
      let(:judge_message) { %(No configured provider serves judge model "#{unknown}") }

      def stranded_prompt
        create(:completion_kit_prompt).tap { |prompt| prompt.update_columns(llm_model: unknown_model) }
      end

      def run_on(prompt: create(:completion_kit_prompt), judge_model: nil, metrics: [], dataset: create(:completion_kit_dataset))
        run = create(:completion_kit_run, prompt: prompt, dataset: dataset)
        run.update_columns(judge_model: judge_model)
        run.replace_metrics!(metrics.map(&:id))
        run
      end

      def judged_run(metrics)
        run = run_on(judge_model: unknown_model, metrics: metrics)
        run.update_columns(status: "completed", progress_total: 1, progress_current: 1)
        create(:completion_kit_response, run: run)
        run
      end

      def new_runs_beside(run)
        CompletionKit::Run.where.not(id: run.id)
      end

      describe "saving a record" do
        it "rejects the prompt model through MCP and REST" do
          result = mcp_call("prompts_create", {"name" => "P", "template" => "Hi", "llm_model" => unknown_model})
          expect_tool_error(result, including: unknown_model)

          post "#{api}/prompts", params: {name: "P", template: "Hi", llm_model: unknown_model}.to_json, headers: api_headers
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.body).to include("is not served by any configured provider")
          expect(CompletionKit::Prompt.where(llm_model: unknown_model)).to be_empty
        end

        it "rejects the judge model through runs_create, runs_update, judges_replay and REST" do
          prompt = create(:completion_kit_prompt)
          dataset = create(:completion_kit_dataset)
          scoring_dataset = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")
          existing = run_on(prompt: prompt, dataset: dataset, judge_model: "gpt-4.1-mini")

          expect_tool_error(mcp_call("runs_create", {"name" => "R", "prompt_id" => prompt.id, "dataset_id" => dataset.id, "judge_model" => unknown_model}), including: unknown_model)
          expect_tool_error(mcp_call("runs_update", {"id" => existing.id, "judge_model" => unknown_model}), including: unknown_model)
          expect_tool_error(mcp_call("judges_replay", {"name" => "J", "metric_id" => llm_metric.id, "dataset_id" => scoring_dataset.id, "judge_model" => unknown_model}), including: unknown_model)

          post "#{api}/runs", params: {name: "R", prompt_id: prompt.id, dataset_id: dataset.id, judge_model: unknown_model}.to_json, headers: api_headers
          expect(response).to have_http_status(:unprocessable_entity)
          patch "#{api}/runs/#{existing.id}", params: {judge_model: unknown_model}.to_json, headers: api_headers
          expect(response).to have_http_status(:unprocessable_entity)

          expect(CompletionKit::Run.where(judge_model: unknown_model)).to be_empty
          expect(existing.reload.judge_model).to eq("gpt-4.1-mini")
        end
      end

      describe "a run whose prompt model does not resolve" do
        it "fails runs_generate with the model named and leaves the run failed, not pending" do
          run = run_on(prompt: stranded_prompt)

          expect_tool_error(mcp_call("runs_generate", {"id" => run.id}), including: model_message)
          expect(run.reload.status).to eq("failed")
          expect(run.failure_summary).to eq(model_message)
        end

        it "answers REST generate with a 422 and the UI Generate action with an alert" do
          run = run_on(prompt: stranded_prompt)

          post "#{api}/runs/#{run.id}/generate", headers: api_headers
          expect(response).to have_http_status(:unprocessable_entity)
          expect(json_error).to eq(model_message)

          post "/completion_kit/runs/#{run.id}/generate"
          expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
          expect(flash[:alert]).to eq(model_message)
          expect(run.reload.status).to eq("failed")
        end

        it "leaves no rerun copy pending through MCP, REST or the UI" do
          run = run_on(prompt: stranded_prompt)

          expect_tool_error(mcp_call("runs_rerun", {"id" => run.id}), including: model_message)

          post "#{api}/runs/#{run.id}/rerun", headers: api_headers
          expect(response).to have_http_status(:unprocessable_entity)
          expect(json_error).to eq(model_message)

          post "/completion_kit/runs/#{run.id}/rerun"
          expect(flash[:alert]).to eq(model_message)

          expect(new_runs_beside(run).pluck(:status)).to eq(%w[failed failed failed])
          expect(new_runs_beside(run).pluck(:failure_summary).uniq).to eq([model_message])
        end

        it "fails prompts_suggest_improvement with the model named" do
          run = run_on(prompt: stranded_prompt)

          expect_tool_error(mcp_call("prompts_suggest_improvement", {"run_id" => run.id}), including: model_message)
        end
      end

      describe "a run whose judge model does not resolve" do
        it "renders the run page and its status poll with an LLM-judge metric" do
          run = judged_run([llm_metric])

          get "/completion_kit/runs/#{run.id}"
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("provider not configured")

          get "/completion_kit/runs/#{run.id}/refresh_status", headers: {"Accept" => "text/vnd.turbo-stream.html"}
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("provider not configured")
        end

        it "renders the run page and its status poll with only a check metric" do
          run = judged_run([check_metric])

          get "/completion_kit/runs/#{run.id}"
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("provider not configured")

          get "/completion_kit/runs/#{run.id}/refresh_status", headers: {"Accept" => "text/vnd.turbo-stream.html"}
          expect(response).to have_http_status(:ok)
        end

        it "refuses to regrade through MCP, REST and the UI, naming the judge" do
          run = judged_run([llm_metric])

          expect_tool_error(mcp_call("runs_regrade", {"id" => run.id}), including: judge_message)

          post "#{api}/runs/#{run.id}/regrade", headers: api_headers
          expect(response).to have_http_status(:unprocessable_entity)
          expect(json_error).to eq(judge_message)

          post "/completion_kit/runs/#{run.id}/regrade"
          expect(flash[:alert]).to eq(judge_message)

          expect(run.reload.status).to eq("completed")
          expect(CompletionKit::JudgeReviewJob).not_to have_received(:perform_later)
        end

        it "fails to start a generating run with an LLM-judge metric before spending tokens" do
          run = run_on(judge_model: unknown_model, metrics: [llm_metric])

          expect_tool_error(mcp_call("runs_generate", {"id" => run.id}), including: judge_message)
          expect(run.reload.status).to eq("failed")
          expect(run.failure_summary).to eq(judge_message)
          expect(CompletionKit::StartRunJob).not_to have_received(:perform_later)
        end

        it "fails a judge-only run with a readable summary" do
          dataset = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")
          run = run_on(prompt: nil, dataset: dataset, judge_model: unknown_model, metrics: [llm_metric])

          post "#{api}/runs/#{run.id}/generate", headers: api_headers

          expect(response).to have_http_status(:unprocessable_entity)
          expect(run.reload.status).to eq("failed")
          expect(run.failure_summary).to eq(judge_message)
        end

        it "lets StartRunJob finish a claimed judge-only run whose judge was retired after it started" do
          dataset = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")
          run = run_on(prompt: nil, dataset: dataset, judge_model: unknown_model, metrics: [llm_metric])
          run.update_columns(status: "running")
          allow(CompletionKit::JudgeReviewJob).to receive(:perform_later) { |*args| CompletionKit::JudgeReviewJob.perform_now(*args) }
          allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later) { |id| CompletionKit::RunCompletionCheckJob.perform_now(id) }

          expect { CompletionKit::StartRunJob.perform_now(run.id) }.not_to raise_error

          review = run.responses.first.reviews.first
          expect(review.status).to eq("failed")
          expect(review.error_message).to eq(model_message)
          expect(run.reload.status).to eq("completed")
        end
      end

      describe "suggesting variants with that model" do
        it "fails metrics_suggest_variants with the model named" do
          expect_tool_error(mcp_call("metrics_suggest_variants", {"metric_id" => llm_metric.id, "model" => unknown_model}), including: model_message)
        end

        it "answers REST suggest_variants with a 422 and keeps the existing drafts" do
          run = run_on(judge_model: "gpt-4.1-mini", metrics: [llm_metric])
          row = create(:completion_kit_response, run: run)
          version = CompletionKit::MetricVersion.ensure_current_for(llm_metric)
          create(:completion_kit_agreement, run: run, response: row, metric: llm_metric, metric_version: version,
                 verdict: "disagree", corrected_score: 2, created_by: "spec")
          draft = create(:completion_kit_metric_version, metric: llm_metric, state: "draft", source: "suggestion", current: false)

          post "#{api}/metrics/#{llm_metric.id}/suggest_variants", params: {model: unknown_model}.to_json, headers: api_headers

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json_error).to eq(model_message)
          expect(CompletionKit::MetricVersion.exists?(draft.id)).to be(true)
        end
      end
    end
  end
end

require "rails_helper"

RSpec.describe "CompletionKit prompts", type: :request do
  let(:base_path) { "/completion_kit/prompts" }
  let(:valid_params) do
    {
      prompt: {
        name: "Email Summarizer",
        description: "Summarizes support emails",
        template: "Summarize {{content}}",
        llm_model: "gpt-4.1"
      }
    }
  end

  it "renders the prompts index" do
    prompt = create(:completion_kit_prompt, name: "Root Prompt")

    get base_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("CompletionKit")
    expect(response.body).to include(prompt.name)
  end

  it "shows a check pass-rate badge alongside best score on the prompts index" do
    prompt = create(:completion_kit_prompt, name: "Checked Prompt")
    check = create(:completion_kit_metric, :check)
    run = create(:completion_kit_run, prompt: prompt)
    run.replace_metrics!([check.id])
    resp = create(:completion_kit_response, run: run)
    create(:completion_kit_review, :check, response: resp, metric: check, passed: true)

    get base_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Checked Prompt")
    expect(response.body).to include("100%")
  end

  it "shows a check pass-rate badge in the versions best-score column" do
    v1 = create(:completion_kit_prompt, name: "Fam Check", family_key: "fam-check", version_number: 1, current: true)
    create(:completion_kit_prompt, name: "Fam Check", family_key: "fam-check", version_number: 2, current: false)
    check = create(:completion_kit_metric, :check)
    run = create(:completion_kit_run, prompt: v1)
    run.replace_metrics!([check.id])
    resp = create(:completion_kit_response, run: run)
    create(:completion_kit_review, :check, response: resp, metric: check, passed: false)

    get "#{base_path}/#{v1.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("0%")
  end

  it "renders the prompt show page without per-run queries (bounded regardless of run count)" do
    v1 = create(:completion_kit_prompt, name: "Perf Fam", family_key: "perf-fam", version_number: 1, current: true)
    metric = create(:completion_kit_metric)
    add_runs = ->(count) do
      count.times do
        run = create(:completion_kit_run, prompt: v1, status: "completed")
        run.replace_metrics!([metric.id])
        response_record = create(:completion_kit_response, run: run, status: "succeeded")
        create(:completion_kit_review, response: response_record, metric: metric, metric_name: "Quality", status: "succeeded", ai_score: 4.0)
      end
    end

    query_count = -> do
      count = 0
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        payload = ActiveSupport::Notifications::Event.new(*args).payload
        count += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/) || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/i)
      end
      get "#{base_path}/#{v1.id}"
      ActiveSupport::Notifications.unsubscribe(sub)
      count
    end

    add_runs.call(2)
    baseline = query_count.call
    add_runs.call(6)
    scaled = query_count.call

    expect(response).to have_http_status(:ok)
    expect(scaled).to eq(baseline)
  end

  it "renders show, new, and edit pages" do
    prompt = create(:completion_kit_prompt, name: "Visible Prompt")

    get "#{base_path}/#{prompt.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visible Prompt")
    expect(response.body).not_to include("ck-vdiff-")

    create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    get "#{base_path}/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Prompt text")
    expect(response.body).to include("OpenAI")

    get "#{base_path}/#{prompt.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visible Prompt")
    expect(response.body).not_to include("saving creates a new version")
  end

  it "exposes the refresh and statuses urls from route helpers so model refresh works on any mount path" do
    create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")

    get "#{base_path}/new"

    expect(response.body).to include(%(data-ck-refresh-url="/completion_kit/refresh_models"))
    expect(response.body).to include(%(data-ck-statuses-url="/completion_kit/provider_credentials/statuses"))
  end

  it "offers a per-version diff modal from the versions table, with a template word-diff when the template changed" do
    create(:completion_kit_prompt, name: "Diffed", family_key: "fam-diff", version_number: 1, current: false, template: "Summarise {{content}}.", llm_model: "gpt-4o")
    v2 = create(:completion_kit_prompt, name: "Diffed", family_key: "fam-diff", version_number: 2, current: true, template: "Summarise {{content}} in two sentences.", llm_model: "gpt-4o")

    get "#{base_path}/#{v2.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ck-cell-link--delta")
    expect(response.body).to include("ck-vdiff-#{v2.id}")
    expect(response.body).to include("ck-suggest-diff")
  end

  it "shows a model change in the diff modal even when the template is unchanged" do
    create(:completion_kit_prompt, name: "Reroled", family_key: "fam-model", version_number: 1, current: false, template: "Same {{x}}", llm_model: "gpt-4o-mini")
    v2 = create(:completion_kit_prompt, name: "Reroled", family_key: "fam-model", version_number: 2, current: true, template: "Same {{x}}", llm_model: "claude-sonnet-4-6")

    get "#{base_path}/#{v2.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ck-vdiff-#{v2.id}")
    expect(response.body).to match(/ck-version-change__old[^>]*>gpt-4o-mini/)
    expect(response.body).to match(/ck-version-change__new[^>]*>claude-sonnet-4-6/)
    expect(response.body).not_to include("ck-suggest-diff")
  end

  it "notes on the edit form that changing the prompt or model saves a new version once that version has runs" do
    prompt = create(:completion_kit_prompt)
    create(:completion_kit_run, prompt: prompt, dataset: create(:completion_kit_dataset))

    get "#{base_path}/#{prompt.id}/edit"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("changing the prompt or model saves a new version")
    expect(response.body).to include("Name and tags update in place")
  end

  it "renders the model refresh button disabled and spinning while discovery is in progress" do
    create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test", discovery_status: "discovering")
    create(:completion_kit_model, provider: "openai", model_id: "gpt-4o", status: "active", supports_generation: true)

    get "#{base_path}/new"

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/<button[^>]*title="Refresh models"[^>]*\bdisabled\b/)
    expect(response.body).to match(/<button[^>]*class="[^"]*ck-icon-btn--spinning[^"]*"[^>]*title="Refresh models"/)
  end

  it "creates a prompt with valid params" do
    expect do
      post base_path, params: valid_params
    end.to change(CompletionKit::Prompt, :count).by(1)

    expect(response).to redirect_to("/completion_kit/prompts/#{CompletionKit::Prompt.last.id}")
  end

  it "renders new when create is invalid" do
    post base_path, params: { prompt: valid_params[:prompt].merge(name: "") }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("prevented this prompt from being saved")
  end

  it "updates a prompt with valid params" do
    prompt = create(:completion_kit_prompt, name: "Old Name")

    patch "#{base_path}/#{prompt.id}", params: { prompt: { name: "New Name" } }

    expect(response).to redirect_to("/completion_kit/prompts/#{prompt.id}")
    expect(prompt.reload.name).to eq("New Name")
  end

  it "renders edit when update is invalid" do
    prompt = create(:completion_kit_prompt, name: "Old Name")

    patch "#{base_path}/#{prompt.id}", params: { prompt: { name: "" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("prevented this prompt from being saved")
  end

  it "creates a new version and publishes it when prompt has existing runs" do
    prompt = create(:completion_kit_prompt, name: "Versioned Prompt", family_key: "family-1", version_number: 1)
    create(:completion_kit_run, prompt: prompt)

    expect do
      patch "#{base_path}/#{prompt.id}", params: { prompt: { name: "Versioned Prompt", template: "Updated {{content}}", llm_model: "gpt-4o" } }
    end.to change(CompletionKit::Prompt, :count).by(1)

    new_prompt = CompletionKit::Prompt.order(:id).last
    expect(response).to redirect_to(%r{/completion_kit/prompts/\d+})
    expect(prompt.reload.template).to eq("Summarize {{content}} for {{audience}}")
    expect(new_prompt.version_number).to eq(2)
    expect(new_prompt.current).to eq(true)
  end

  it "updates name and tags in place without a new version when only metadata changed on a prompt with runs" do
    prompt = create(:completion_kit_prompt, name: "Original", family_key: "family-meta", version_number: 1)
    create(:completion_kit_run, prompt: prompt)

    expect do
      patch "#{base_path}/#{prompt.id}", params: { prompt: {
        name: "Renamed", template: prompt.template, llm_model: prompt.llm_model, tag_names: ["metaonly"]
      } }
    end.not_to change(CompletionKit::Prompt, :count)

    expect(response).to redirect_to("#{base_path}/#{prompt.id}")
    expect(prompt.reload.name).to eq("Renamed")
    expect(prompt.tag_names).to eq(["metaonly"])
  end

  it "returns 422 instead of 500 when re-versioning onto a model that can't generate" do
    CompletionKit::Model.create!(provider: "azure_foundry", model_id: "demoted-x",
      status: "active", supports_generation: false, supports_judging: false)
    prompt = create(:completion_kit_prompt, name: "Demoted Reversion", family_key: "family-demoted", version_number: 1)
    create(:completion_kit_run, prompt: prompt)

    expect do
      patch "#{base_path}/#{prompt.id}", params: { prompt: { template: "Updated {{content}}", llm_model: "demoted-x" } }
    end.not_to change(CompletionKit::Prompt, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("is not available for generating responses")
  end

  it "returns 422 instead of 500 when re-versioning with a malformed tag name" do
    prompt = create(:completion_kit_prompt, family_key: "family-badtag", version_number: 1)
    create(:completion_kit_run, prompt: prompt)

    expect do
      patch "#{base_path}/#{prompt.id}", params: { prompt: { template: "Updated {{content}}", tag_names: ["c++"] } }
    end.not_to change(CompletionKit::Prompt, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("not allowed")
  end

  it "keeps the submitted tag selection when a re-version fails validation" do
    CompletionKit::Tag.create!(name: "keepme")
    CompletionKit::Model.create!(provider: "azure_foundry", model_id: "demoted-z",
      status: "active", supports_generation: false, supports_judging: false)
    prompt = create(:completion_kit_prompt, family_key: "family-preserve", version_number: 1)
    create(:completion_kit_run, prompt: prompt)

    patch "#{base_path}/#{prompt.id}", params: { prompt: { llm_model: "demoted-z", tag_names: ["keepme"] } }

    expect(response).to have_http_status(:unprocessable_entity)
    box = Nokogiri::HTML5(response.body).at_css('input[type="checkbox"][value="keepme"]')
    expect(box).to be_present
    expect(box.key?("checked")).to be(true)
  end

  it "keeps a newly-typed tag name (and creates no orphan) when a re-version fails validation" do
    CompletionKit::Model.create!(provider: "azure_foundry", model_id: "demoted-w",
      status: "active", supports_generation: false, supports_judging: false)
    prompt = create(:completion_kit_prompt, family_key: "family-newtag", version_number: 1)
    create(:completion_kit_run, prompt: prompt)

    patch "#{base_path}/#{prompt.id}", params: { prompt: { llm_model: "demoted-w", tag_names: ["freshly-typed"] } }

    expect(response).to have_http_status(:unprocessable_entity)
    box = Nokogiri::HTML5(response.body).at_css('input[type="checkbox"][value="freshly-typed"]')
    expect(box).to be_present
    expect(box.key?("checked")).to be(true)
    expect(CompletionKit::Tag.where(name: "freshly-typed")).not_to exist
  end

  it "applies tag_names to the cloned version when prompt has existing runs" do
    prompt = create(:completion_kit_prompt, name: "Tagged Versioned", family_key: "family-tagged", version_number: 1)
    create(:completion_kit_run, prompt: prompt)

    patch "#{base_path}/#{prompt.id}", params: {
      prompt: { name: "Tagged Versioned", template: "Updated {{content}}",
                llm_model: "gpt-4o", tag_names: ["alpha"] }
    }

    new_prompt = CompletionKit::Prompt.order(:id).last
    expect(new_prompt.tag_names).to eq(["alpha"])
  end

  it "publishes a version as current" do
    current_prompt = create(:completion_kit_prompt, name: "Family Prompt", family_key: "family-2", version_number: 1, current: true)
    draft_prompt = create(:completion_kit_prompt, name: "Family Prompt", family_key: "family-2", version_number: 2, current: false, published_at: nil)

    post "/completion_kit/prompts/#{draft_prompt.id}/publish"

    expect(response).to redirect_to("/completion_kit/prompts/#{draft_prompt.id}")
    expect(current_prompt.reload.current).to eq(false)
    expect(draft_prompt.reload.current).to eq(true)
  end


  it "destroys a prompt" do
    prompt = create(:completion_kit_prompt)

    expect do
      delete "#{base_path}/#{prompt.id}"
    end.to change(CompletionKit::Prompt, :count).by(-1)

    expect(response).to redirect_to("/completion_kit/prompts")
  end

  it "lists versions: Published badge for the current one, Publish button for the others, the viewed row highlighted, clickable rows, per-version diff link" do
    v1 = create(:completion_kit_prompt, name: "Prompt", family_key: "fam-1", version_number: 1, current: true, template: "v1 {{x}}")
    v2 = create(:completion_kit_prompt, name: "Prompt", family_key: "fam-1", version_number: 2, current: false, template: "v2 {{x}}")

    get "/completion_kit/prompts/#{v2.id}"

    expect(response.body).to include("Published")
    expect(response.body).to include("Publish")
    expect(response.body).to include("/completion_kit/prompts/#{v1.id}")
    expect(response.body).to include("ck-results-table__row--active")
    expect(response.body).to include("ck-cell-link--delta")
    expect(response.body).to include("ck-vdiff-#{v2.id}")
  end

  it "round-trips tag_names on create and update" do
    post "/completion_kit/prompts", params: {
      prompt: { name: "P", template: "hi", llm_model: "gpt-4o-mini",
                tag_names: ["alpha"] }
    }
    prompt = CompletionKit::Prompt.find_by!(name: "P")
    expect(prompt.tag_names).to eq(["alpha"])

    patch "/completion_kit/prompts/#{prompt.id}", params: {
      prompt: { tag_names: [] }
    }
    expect(prompt.reload.tag_names).to eq([])
  end

  it "filters prompts by tag" do
    marine_prompt = create(:completion_kit_prompt, name: "Shark classifier")
    real_estate_prompt = create(:completion_kit_prompt, name: "Property listing writer")
    marine_prompt.update!(tag_names: ["marine biology"])
    real_estate_prompt.update!(tag_names: ["real estate"])

    get "/completion_kit/prompts?tag[]=marine biology"
    expect(response.body).to include("Shark classifier")
    expect(response.body).not_to include("Property listing writer")

    get "/completion_kit/prompts?tag[]=marine biology&tag[]=real estate"
    expect(response.body).to include("Shark classifier")
    expect(response.body).to include("Property listing writer")

    get "/completion_kit/prompts"
    expect(response.body).to include("Shark classifier")
    expect(response.body).to include("Property listing writer")
  end

  it "renders no filter bar when no tags exist" do
    create(:completion_kit_prompt, name: "Helpfulness")
    get "/completion_kit/prompts"
    expect(response.body).not_to include("Filter by tag")
  end

  it "shows the filter bar when tags exist" do
    CompletionKit::Tag.create!(name: "z")
    create(:completion_kit_prompt, name: "Helpfulness")
    get "/completion_kit/prompts"
    expect(response.body).to include("Filter by tag")
  end

  it "scopes the prompt's run list and renders the display footer with shown runs" do
    prompt = create(:completion_kit_prompt, name: "Prompt A")
    create(:completion_kit_run, prompt: prompt, name: "Recent Prompt Run")
    create(:completion_kit_run, prompt: prompt, name: "Old Prompt Run", created_at: 90.days.ago)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }
    CompletionKit.config.runs_display_footer_partial = "spec_host/runs_footer"

    get "/completion_kit/prompts/#{prompt.id}"

    expect(response.body).to include("Recent Prompt Run")
    expect(response.body).not_to include("Old Prompt Run")
    expect(response.body).to include("spec-host-runs-footer: 1 runs in view")
  ensure
    CompletionKit.config.runs_display_footer_partial = nil
    CompletionKit.config.runs_display_scope = nil
  end

  it "scopes the prompt family run count cell to display-scoped runs" do
    prompt = create(:completion_kit_prompt, name: "Counted Prompt")
    create(:completion_kit_run, prompt: prompt)
    create(:completion_kit_run, prompt: prompt, created_at: 90.days.ago)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    get "/completion_kit/prompts"

    expect(response.body).to match(/ck-prompts-table__runs-count">1</)
  ensure
    CompletionKit.config.runs_display_scope = nil
  end

  it "scopes the index best-score badge to display-scoped runs" do
    prompt = create(:completion_kit_prompt, name: "Scored Prompt")
    create(:completion_kit_review, response: create(:completion_kit_response, run: create(:completion_kit_run, prompt: prompt)), ai_score: 2.0)
    old = create(:completion_kit_run, prompt: prompt, created_at: 90.days.ago)
    create(:completion_kit_review, response: create(:completion_kit_response, run: old), ai_score: 5.0)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    get "/completion_kit/prompts"

    expect(response.body).to include(">2.0<")
    expect(response.body).not_to include(">5.0<")
  ensure
    CompletionKit.config.runs_display_scope = nil
  end

  it "renders the delete control as its own top-level form so it issues DELETE, not a Turbo-swallowed PATCH" do
    record = create(:completion_kit_prompt)

    get "#{base_path}/#{record.id}/edit"

    doc = Nokogiri::HTML5(response.body)
    target = "#{base_path}/#{record.id}"
    forms = doc.css("form").select { |f| f["action"] == target }
    patch_form = forms.find { |f| f.css("input[name='_method']").any? { |i| i["value"] == "patch" } }
    delete_form = forms.find { |f| f.css("input[name='_method']").any? { |i| i["value"] == "delete" } }

    expect(patch_form).to be_present
    expect(delete_form).to be_present
    expect(patch_form).not_to eq(delete_form)

    expect(delete_form["id"]).to be_present
    trigger = doc.at_css("button[type='submit'][form='#{delete_form["id"]}']")
    expect(trigger).to be_present
    expect(trigger["data-turbo-confirm"]).to be_present
  end

end

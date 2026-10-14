require "rails_helper"

RSpec.describe "CompletionKit pages under a nonce-based script policy", type: :request do
  let(:policy) do
    ActionDispatch::ContentSecurityPolicy.new do |p|
      p.default_src :self
      p.script_src :self
      p.style_src :self, :unsafe_inline
    end
  end

  let(:tag) { create(:completion_kit_tag, name: "support") }
  let(:dataset) { create(:completion_kit_dataset) }
  let(:judge_metric) { create(:completion_kit_metric, instruction: "Score the answer") }
  let(:check_metric) { create(:completion_kit_metric, :check) }
  let(:metric_group) { create(:completion_kit_metric_group) }
  let(:family_key) { SecureRandom.uuid }
  let(:first_prompt) { create(:completion_kit_prompt, family_key: family_key, version_number: 1, current: false, template: "Summarize {{content}}") }
  let(:prompt) { create(:completion_kit_prompt, family_key: family_key, version_number: 2, current: true, template: "Summarize {{content}} for {{audience}}. #{"Keep every claim grounded in the source passage. " * 6}") }
  let(:run) { create(:completion_kit_run, prompt: prompt, dataset: dataset, status: "running", judge_model: "gpt-4.1-mini") }
  let(:other_run) { create(:completion_kit_run, prompt: first_prompt, dataset: dataset, status: "completed") }
  let(:succeeded) { create(:completion_kit_response, run: run) }
  let(:credential) { create(:completion_kit_provider_credential, provider: "openai") }
  let(:empty_credential) { create(:completion_kit_provider_credential, provider: "anthropic") }
  let(:draft_version) do
    CompletionKit::MetricVersion.ensure_current_for(judge_metric)
    CompletionKit::MetricVersion.create!(metric: judge_metric, instruction: "Score the answer against the source",
                                         rubric_bands: judge_metric.rubric_bands, state: "draft", source: "suggestion", current: false)
  end

  before do
    allow(Rails.application).to receive(:env_config).and_wrap_original do |original|
      original.call.merge(
        "action_dispatch.content_security_policy" => policy,
        "action_dispatch.content_security_policy_nonce_generator" => ->(_request) { SecureRandom.base64(16) },
        "action_dispatch.content_security_policy_nonce_directives" => %w[script-src]
      )
    end

    [judge_metric, check_metric, dataset, run].each { |record| create(:completion_kit_tagging, tag: tag, taggable: record) }
    create(:completion_kit_metric_group_membership, metric_group: metric_group, metric: judge_metric)
    create(:completion_kit_metric_group_membership, metric_group: metric_group, metric: check_metric)
    run.replace_metrics!([judge_metric.id, check_metric.id])
    other_run.replace_metrics!([judge_metric.id])
    succeeded
    create(:completion_kit_response, :failed, run: run)
    create(:completion_kit_response, run: other_run)
    create(:completion_kit_suggestion, run: other_run, prompt: first_prompt)
    create(:completion_kit_model, provider: "openai", model_id: "gpt-4o")
    credential.update_columns(discovery_status: "completed")
    empty_credential.update_columns(discovery_status: "completed")
    draft_version
    CompletionKit.config.api_token = "csp-spec-token-0123456789"
  end

  after { CompletionKit.config.api_token = nil }

  def expect_nonce_only_scripts(path)
    get path

    expect(response).to have_http_status(:ok)
    nonce = response.headers["Content-Security-Policy"].to_s[/'nonce-([^']+)'/, 1]
    expect(nonce).to be_present

    document = Nokogiri::HTML5(response.body)
    handlers = document.xpath("//@*[starts-with(local-name(), 'on')]").map { |attribute| "#{attribute.parent.name}[#{attribute.name}]" }
    unsigned = document.css("script").reject { |script| script["nonce"] == nonce }.map { |script| script.to_html.truncate(120) }

    expect(handlers).to be_empty, "#{path} has inline handlers: #{handlers.uniq.join(", ")}"
    expect(unsigned).to be_empty, "#{path} has scripts without the request nonce: #{unsigned.join(" | ")}"
    expect(document.css("script")).not_to be_empty
    expect(document.at_css('meta[name="csp-nonce"]')["content"]).to eq(nonce)
  end

  it "renders the prompt pages with no inline handlers and only nonce scripts" do
    %W[
      /completion_kit/prompts
      /completion_kit/prompts/#{prompt.id}
      /completion_kit/prompts/new
      /completion_kit/prompts/#{prompt.id}/edit
    ].each { |path| expect_nonce_only_scripts(path) }
  end

  it "renders the metric pages with no inline handlers and only nonce scripts" do
    starter = CompletionKit::StarterMetrics::ALL.first
    %W[
      /completion_kit/metrics
      /completion_kit/metrics/#{judge_metric.id}
      /completion_kit/metrics/#{judge_metric.id}?show_change=#{draft_version.id}
      /completion_kit/metrics/#{check_metric.id}
      /completion_kit/metrics/new
      /completion_kit/metrics/#{judge_metric.id}/edit
      /completion_kit/metrics/#{check_metric.id}/edit
      /completion_kit/metrics/starters/#{starter.key}
    ].each { |path| expect_nonce_only_scripts(path) }
  end

  it "renders the metric group pages with no inline handlers and only nonce scripts" do
    %W[
      /completion_kit/metric_groups
      /completion_kit/metric_groups/#{metric_group.id}
      /completion_kit/metric_groups/new
      /completion_kit/metric_groups/#{metric_group.id}/edit
    ].each { |path| expect_nonce_only_scripts(path) }
  end

  it "renders the dataset pages with no inline handlers and only nonce scripts" do
    %W[
      /completion_kit/datasets
      /completion_kit/datasets/#{dataset.id}
      /completion_kit/datasets/new
      /completion_kit/datasets/#{dataset.id}/edit
    ].each { |path| expect_nonce_only_scripts(path) }
  end

  it "renders the run and response pages with no inline handlers and only nonce scripts" do
    %W[
      /completion_kit/runs
      /completion_kit/runs/#{run.id}
      /completion_kit/runs/new
      /completion_kit/runs/#{run.id}/edit
      /completion_kit/runs/#{run.id}/compare?with=#{other_run.id}
      /completion_kit/runs/#{run.id}/responses/#{succeeded.id}
    ].each { |path| expect_nonce_only_scripts(path) }
  end

  it "renders the provider, tag, suggestion and settings pages with no inline handlers and only nonce scripts" do
    suggestion = CompletionKit::Suggestion.last
    %W[
      /completion_kit/provider_credentials
      /completion_kit/provider_credentials/new
      /completion_kit/provider_credentials/#{credential.id}/edit
      /completion_kit/provider_credentials/#{empty_credential.id}/edit
      /completion_kit/tags
      /completion_kit/tags/new
      /completion_kit/tags/#{tag.id}/edit
      /completion_kit/suggestions/#{suggestion.id}
      /completion_kit/dashboard
      /completion_kit/onboarding?reset=1
      /completion_kit/api_reference
    ].each { |path| expect_nonce_only_scripts(path) }
  end

  it "marks every interactive element with the data attribute the engine script listens for" do
    hooks = {
      "/completion_kit/prompts" => ["tr[data-ck-href]", "[data-ck-row-ignore] [data-ck-copy]"],
      "/completion_kit/prompts/#{prompt.id}" => ["tr[data-ck-href]", "[data-ck-row-ignore] a", "[data-ck-dialog-open]", "dialog[data-ck-dialog] [data-ck-dialog-close]", "[data-ck-copy='prompt_endpoint']"],
      "/completion_kit/prompts/new" => ["[data-ck-refresh-models]"],
      "/completion_kit/metrics" => ["tr[data-ck-href]", "form[data-ck-stop-propagation]"],
      "/completion_kit/metrics/#{judge_metric.id}?show_change=#{draft_version.id}" => ["[data-ck-dialog-open='ck-mvdiff-#{draft_version.id}']", "dialog#ck-mvdiff-#{draft_version.id}[data-ck-dialog-autoopen]"],
      "/completion_kit/metric_groups/#{metric_group.id}/edit" => ["[data-metric-tag-filter] [data-filter-tag]"],
      "/completion_kit/runs" => ["tr[data-ck-href]"],
      "/completion_kit/runs/#{run.id}" => ["tr[data-ck-href]", "[data-ck-run-status-url='/completion_kit/runs/#{run.id}/refresh_status']", "[data-ck-dialog-open='dataset-preview-#{run.id}']", "[data-ck-prompt-toggle][aria-controls='prompt_text']"],
      "/completion_kit/runs/new" => ["[data-metric-group][data-metric-ids]", "[data-metric-tag-filter] [data-filter-tag]", "[data-ck-refresh-models]"],
      "/completion_kit/provider_credentials/#{credential.id}/edit" => ["summary [data-ck-provider-refresh='/completion_kit/provider_credentials/#{credential.id}/refresh']"],
      "/completion_kit/provider_credentials/#{empty_credential.id}/edit" => ["[data-ck-provider-refresh='/completion_kit/provider_credentials/#{empty_credential.id}/refresh']"],
      "/completion_kit/tags" => ["tr[data-ck-href]"],
      "/completion_kit/api_reference" => ["[data-ck-token-toggle]", "[data-ck-copy-text='csp-spec-token-0123456789'][data-ck-copy-feedback]", "[data-ck-copy-example]", "[data-ck-copy]"]
    }

    missing = hooks.flat_map do |path, selectors|
      get path
      document = Nokogiri::HTML5(response.body)
      selectors.reject { |selector| document.at_css(selector) }.map { |selector| "#{path} #{selector}" }
    end

    expect(missing).to be_empty
  end

  it "opens a version change dialog and polls a run's status only when the page asks for it" do
    get "/completion_kit/metrics/#{judge_metric.id}"
    expect(Nokogiri::HTML5(response.body).at_css("[data-ck-dialog-autoopen]")).to be_nil

    get "/completion_kit/runs/#{other_run.id}"
    expect(Nokogiri::HTML5(response.body).at_css("[data-ck-run-status-url]")).to be_nil
  end

  it "keeps inline event handlers and onclick helper options out of every engine template" do
    event_handler = /on(?:abort|auxclick|blur|cancel|change|click|close|contextmenu|copy|cut|dblclick|drag[a-z]*|drop|error|focus[a-z]*|input|invalid|key[a-z]+|load|mouse[a-z]+|paste|pointer[a-z]+|reset|resize|scroll|select|submit|toggle|touch[a-z]+|wheel)\b/
    templates = Dir[CompletionKit::Engine.root.join("app/views/**/*.erb").to_s]
    offenders = templates.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        next unless line.match?(/\son[a-z]+\s*=\s*["']/) || line.match?(/\b#{event_handler}:/) || line.match?(/["']#{event_handler}["']\s*=>/)

        "#{path.delete_prefix("#{CompletionKit::Engine.root}/")}:#{index + 1}"
      end
    end

    expect(offenders).to be_empty
  end
end

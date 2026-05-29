require "rails_helper"

RSpec.describe CompletionKit::ApplicationHelper, type: :helper do
  describe "#ck_button_classes" do
    it "covers every button style branch" do
      expect(helper.ck_button_classes(:dark)).to include("ck-button--primary")
      expect(helper.ck_button_classes(:light, variant: :outline)).to include("ck-button--secondary")
      expect(helper.ck_button_classes(:green)).to include("ck-button--success")
      expect(helper.ck_button_classes(:red, variant: :outline)).to include("ck-button--danger")
      expect(helper.ck_button_classes(:amber, variant: :outline)).to include("ck-button--warning")
      expect(helper.ck_button_classes(:blue, variant: :outline)).to include("ck-button--info")
      expect(helper.ck_button_classes(:unknown, variant: :ghost)).to include("ck-button--primary")
    end
  end

  describe "#ck_badge_classes" do
    it "covers every badge style branch" do
      expect(helper.ck_badge_classes(:high)).to include("ck-badge--high")
      expect(helper.ck_badge_classes(:medium)).to include("ck-badge--medium")
      expect(helper.ck_badge_classes(:low)).to include("ck-badge--low")
      expect(helper.ck_badge_classes(:pending)).to include("ck-badge--pending")
      expect(helper.ck_badge_classes(:running)).to include("ck-badge--running")
      expect(helper.ck_badge_classes(:completed)).to include("ck-badge--high")
      expect(helper.ck_badge_classes(:failed)).to include("ck-badge--low")
      expect(helper.ck_badge_classes(:mystery)).to include("ck-badge--pending")
    end
  end

  describe "#ck_run_dot" do
    def stub_run(status)
      instance_double(CompletionKit::Run, status: status)
    end

    it "returns pending dot for pending status" do
      expect(helper.ck_run_dot(stub_run("pending"))).to eq("ck-dot ck-dot--pending")
    end

    it "returns running dot for running status" do
      expect(helper.ck_run_dot(stub_run("running"))).to eq("ck-dot ck-dot--running")
    end

    it "returns failed dot for failed status" do
      expect(helper.ck_run_dot(stub_run("failed"))).to eq("ck-dot ck-dot--failed")
    end

    it "returns completed dot for completed status" do
      expect(helper.ck_run_dot(stub_run("completed"))).to eq("ck-dot ck-dot--completed")
    end

    it "returns pending dot for unknown status" do
      expect(helper.ck_run_dot(stub_run("unknown_state"))).to eq("ck-dot ck-dot--pending")
    end
  end

  describe "#ck_grouped_models" do
    it "returns grouped options for select" do
      models = [{ id: "gpt-4", name: "GPT-4", provider: "openai" }]
      result = helper.ck_grouped_models(models, "gpt-4")
      expect(result).to include("GPT-4")
      expect(result).to include("OpenAI")
    end

    it "appends retired model when selected model is not in list" do
      create(:completion_kit_model, provider: "openai", model_id: "gpt-old", display_name: "GPT Old", status: "retired")
      models = [{ id: "gpt-4", name: "GPT-4", provider: "openai" }]
      result = helper.ck_grouped_models(models, "gpt-old")
      expect(result).to include("GPT Old (retired)")
    end

    it "does not append when selected model is already present" do
      models = [{ id: "gpt-4", name: "GPT-4", provider: "openai" }]
      result = helper.ck_grouped_models(models, "gpt-4")
      expect(result).not_to include("retired")
    end

    it "handles selected model not found in registry" do
      models = [{ id: "gpt-4", name: "GPT-4", provider: "openai" }]
      result = helper.ck_grouped_models(models, "nonexistent")
      expect(result).not_to include("retired")
    end

    it "marks judge options that are not yet confirmed with (?)" do
      models = [
        { id: "openai/confirmed", name: "Confirmed", provider: "openrouter", judging_confirmed: true },
        { id: "openai/untested", name: "Untested", provider: "openrouter", judging_confirmed: false }
      ]
      result = helper.ck_grouped_models(models)
      expect(result).to include("Untested (?)")
      expect(result).to include(">Confirmed<")
      expect(result).not_to include("Confirmed (?)")
    end
  end

  describe "#ck_grouped_models with openrouter" do
    it "splits openrouter models into optgroups by upstream namespace and openai by family" do
      models = [
        { id: "gpt-4.1-mini", name: "GPT-4.1 Mini", provider: "openai" },
        { id: "openai/gpt-4o-mini", name: "GPT-4o Mini", provider: "openrouter" },
        { id: "openai/gpt-5", name: "GPT-5", provider: "openrouter" },
        { id: "anthropic/claude-sonnet", name: "Claude Sonnet", provider: "openrouter" },
        { id: "~anthropic/claude-sonnet-latest", name: "Claude Sonnet latest", provider: "openrouter" },
        { id: "meta-llama/llama-3.3-70b", name: "Llama 3.3 70B", provider: "openrouter" }
      ]
      html = helper.ck_grouped_models(models)
      expect(html).to include('label="OpenAI — GPT-4"')
      expect(html).to include('label="OpenRouter — openai"')
      expect(html).to include('label="OpenRouter — anthropic"') # ~anthropic merged in
      expect(html).to include('label="OpenRouter — meta-llama"')
    end

    it "groups openai models by family in a sensible order, ahead of other direct providers" do
      models = [
        { id: "o3-mini", name: "o3 Mini", provider: "openai" },
        { id: "gpt-4o", name: "GPT-4o", provider: "openai" },
        { id: "gpt-5.4", name: "GPT-5.4", provider: "openai" },
        { id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", provider: "anthropic" }
      ]
      html = helper.ck_grouped_models(models)
      labels = html.scan(/label="([^"]+)"/).flatten
      expect(labels).to eq(["OpenAI — GPT-5", "OpenAI — GPT-4", "OpenAI — o-series", "Anthropic"])
    end

    it "groups other direct providers as a single optgroup" do
      models = [{ id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", provider: "anthropic" }]
      html = helper.ck_grouped_models(models)
      expect(html).to include('label="Anthropic"')
    end
  end

  describe "#ck_openai_model_family" do
    it "buckets openai model ids by family" do
      expect(helper.ck_openai_model_family("gpt-5.4-mini")).to eq("GPT-5")
      expect(helper.ck_openai_model_family("gpt-4o")).to eq("GPT-4")
      expect(helper.ck_openai_model_family("gpt-4.1-nano")).to eq("GPT-4")
      expect(helper.ck_openai_model_family("gpt-3.5-turbo")).to eq("GPT-3.5")
      expect(helper.ck_openai_model_family("gpt-oss-120b")).to eq("GPT-OSS")
      expect(helper.ck_openai_model_family("o1")).to eq("o-series")
      expect(helper.ck_openai_model_family("o3-mini")).to eq("o-series")
      expect(helper.ck_openai_model_family("o4-mini-high")).to eq("o-series")
      expect(helper.ck_openai_model_family("chatgpt-4o-latest")).to eq("Other")
    end
  end

  describe "#ck_model_table_sections" do
    def model(provider, id) = CompletionKit::Model.new(provider: provider, model_id: id)

    it "groups openrouter models by upstream vendor, alphabetically, merging ~aliases" do
      models = [
        model("openrouter", "meta-llama/llama-3.3-70b"),
        model("openrouter", "anthropic/claude-sonnet-4.6"),
        model("openrouter", "openai/gpt-4o-mini"),
        model("openrouter", "~anthropic/claude-sonnet-latest")
      ]
      sections = helper.ck_model_table_sections(models)
      expect(sections.map(&:first)).to eq(%w[anthropic meta-llama openai])
      expect(sections.first.last.map(&:model_id)).to contain_exactly("anthropic/claude-sonnet-4.6", "~anthropic/claude-sonnet-latest")
    end

    it "groups openai models by family in a sensible order, extras last" do
      models = [
        model("openai", "o3-mini"),
        model("openai", "gpt-4o"),
        model("openai", "gpt-5.4"),
        model("openai", "chatgpt-4o-latest"),
        model("openai", "gpt-3.5-turbo")
      ]
      expect(helper.ck_model_table_sections(models).map(&:first)).to eq(["GPT-5", "GPT-4", "o-series", "GPT-3.5", "Other"])
    end

    it "leaves other providers flat with no section label" do
      models = [model("anthropic", "claude-opus-4-7"), model("anthropic", "claude-haiku-4-5")]
      sections = helper.ck_model_table_sections(models)
      expect(sections.size).to eq(1)
      expect(sections.first.first).to be_nil
      expect(sections.first.last.size).to eq(2)
    end

    it "collapses a single section to a nil label" do
      sections = helper.ck_model_table_sections([model("openai", "gpt-4o"), model("openai", "gpt-4.1-mini")])
      expect(sections).to eq([[nil, sections.first.last]])
    end

    it "handles an empty list" do
      expect(helper.ck_model_table_sections([])).to eq([[nil, []]])
    end
  end

  describe "#ck_model_options_html" do
    it "returns empty string when no models exist for scope" do
      result = helper.ck_model_options_html(:generation)
      expect(result).to eq("")
    end

    it "returns grouped options html when models exist for scope" do
      create(:completion_kit_model, provider: "openai", model_id: "gpt-test", supports_generation: true, status: "active")
      result = helper.ck_model_options_html(:generation)
      expect(result).to include("gpt-test")
    end
  end

  describe "#ck_score_kind" do
    it "returns the expected score bands" do
      expect(helper.ck_score_kind(nil)).to eq(:pending)
      expect(helper.ck_score_kind(4.5)).to eq(:high)
      expect(helper.ck_score_kind(3.5)).to eq(:medium)
      expect(helper.ck_score_kind(2.0)).to eq(:low)
    end
  end

  describe "#ck_word_diff_old" do
    it "marks removed words in old text and skips additions" do
      result = helper.ck_word_diff_old("hello world", "hello universe")
      expect(result).to include("ck-diff-del")
      expect(result).to include("world")
      expect(result).not_to include("ck-diff-ins")
    end

    it "returns unchanged text when texts are identical" do
      result = helper.ck_word_diff_old("hello world", "hello world")
      expect(result).not_to include("ck-diff")
      expect(result).to include("hello")
    end
  end

  describe "#ck_word_diff_new" do
    it "marks added words in new text and skips removals" do
      result = helper.ck_word_diff_new("hello world", "hello universe")
      expect(result).to include("ck-diff-ins")
      expect(result).to include("universe")
      expect(result).not_to include("ck-diff-del")
    end

    it "handles nil inputs" do
      result = helper.ck_word_diff_new(nil, "hello")
      expect(result).to include("hello")
    end
  end

  describe "#tag_pill_class" do
    let(:tag) { CompletionKit::Tag.create!(name: "x") }

    it "returns filled classes by default" do
      expect(helper.tag_pill_class(tag)).to eq("tag tag-#{tag.color}")
    end

    it "adds tag-outline when outline is true" do
      expect(helper.tag_pill_class(tag, outline: true)).to eq("tag tag-#{tag.color} tag-outline")
    end
  end

  describe "#tag_filter_url" do
    let(:base) { "/completion_kit/metrics" }
    let(:tag_a) { CompletionKit::Tag.create!(name: "a") }
    let(:tag_b) { CompletionKit::Tag.create!(name: "b") }

    it "adds the tag when not currently selected" do
      expect(helper.tag_filter_url(base, [], tag_a)).to eq("#{base}?tag%5B%5D=a")
    end

    it "removes the tag when currently selected" do
      expect(helper.tag_filter_url(base, [tag_a], tag_a)).to eq(base)
    end

    it "preserves other selected tags when toggling" do
      url = helper.tag_filter_url(base, [tag_a, tag_b], tag_a)
      expect(url).to eq("#{base}?tag%5B%5D=b")
    end
  end

  describe "engine path helpers" do
    let(:run) { instance_double(CompletionKit::Run, to_param: "42") }
    let(:prompt) { instance_double(CompletionKit::Prompt, to_param: "the-prompt") }
    let(:dataset) { instance_double(CompletionKit::Dataset, to_param: "the-dataset") }

    it "returns a plain engine path when there is no recall context" do
      allow(helper).to receive(:url_options).and_return({})
      expect(helper.ck_run_path(run)).to eq("/completion_kit/runs/42")
      expect(helper.ck_prompt_path(prompt)).to eq("/completion_kit/prompts/the-prompt")
      expect(helper.ck_dataset_path(dataset)).to eq("/completion_kit/datasets/the-dataset")
    end

    it "passes recall segments (minus controller/action) as explicit kwargs so dynamic mount scopes resolve" do
      allow(helper).to receive(:url_options).and_return(
        _recall: { controller: "completion_kit/runs", action: "index", org_slug: "acme" }
      )
      engine_helpers = CompletionKit::Engine.routes.url_helpers
      expect(engine_helpers).to receive(:run_path).with(run, org_slug: "acme").and_return("/orgs/acme/runs/42")
      expect(engine_helpers).to receive(:prompt_path).with(prompt, org_slug: "acme").and_return("/orgs/acme/prompts/the-prompt")
      expect(engine_helpers).to receive(:dataset_path).with(dataset, org_slug: "acme").and_return("/orgs/acme/datasets/the-dataset")
      expect(helper.ck_run_path(run)).to eq("/orgs/acme/runs/42")
      expect(helper.ck_prompt_path(prompt)).to eq("/orgs/acme/prompts/the-prompt")
      expect(helper.ck_dataset_path(dataset)).to eq("/orgs/acme/datasets/the-dataset")
    end
  end

  describe "#ck_format_maybe_json" do
    it "returns the input unchanged when blank or whitespace-only" do
      expect(helper.ck_format_maybe_json("")).to eq("")
      expect(helper.ck_format_maybe_json("   \n  ")).to eq("   \n  ")
      expect(helper.ck_format_maybe_json(nil)).to eq("")
    end

    it "returns the input unchanged when it doesn't start with { or [" do
      expect(helper.ck_format_maybe_json("Hello world")).to eq("Hello world")
    end

    it "pretty-prints a JSON object and wraps keys, strings, numbers, and keywords (true/false/null) in highlight spans" do
      out = helper.ck_format_maybe_json('{"name":"Alice","age":30,"admin":true,"banned":false,"deleted_at":null,"tags":["x"]}')
      expect(out).to include('class="ck-json-key"', '&quot;name&quot;')
      expect(out).to include('class="ck-json-string"', '&quot;Alice&quot;')
      expect(out).to include('class="ck-json-number"', '30')
      expect(out).to include('class="ck-json-keyword"', 'true')
      expect(out).to include('class="ck-json-keyword"', 'false')
      expect(out).to include('class="ck-json-keyword"', 'null')
      expect(out).to include('class="ck-json-punct"', '{')
      expect(out).to be_html_safe
    end

    it "pretty-prints a JSON array with negative and decimal numbers wrapped in number spans" do
      out = helper.ck_format_maybe_json('[-1, 1.5]')
      expect(out).to include("-1")
      expect(out).to include("1.5")
      expect(out).to include('class="ck-json-number"')
    end

    it "tokenizes scientific-notation numbers when handed pretty-printed JSON directly" do
      out = helper.ck_highlight_json("[1.5e3, -2E-1]")
      expect(out).to include('class="ck-json-number"')
      expect(out).to include("1.5e3")
      expect(out).to include("-2E-1")
    end

    it "preserves strings that contain escaped quotes" do
      out = helper.ck_format_maybe_json('{"k":"he said \"hi\""}')
      expect(out).to include('class="ck-json-string"')
      expect(out).to include('he said')
    end

    it "uses ck-json-string (not ck-json-key) for plain string values" do
      out = helper.ck_format_maybe_json('["alpha"]')
      expect(out).to include('class="ck-json-string"')
      expect(out).not_to include('class="ck-json-key">&quot;alpha&quot;</span>')
    end

    it "returns the raw input when JSON parsing fails" do
      malformed = '{"oops": '
      expect(helper.ck_format_maybe_json(malformed)).to eq(malformed)
    end

    it "unwraps a ```json fenced response and highlights the inner JSON" do
      fenced = "```json\n{\"score\":4,\"why\":\"clear\"}\n```"
      out = helper.ck_format_maybe_json(fenced)
      expect(out).to include('class="ck-json-key"')
      expect(out).to include("&quot;score&quot;")
      expect(out).to include("4")
    end

    it "unwraps an unlabeled triple-backtick fence as well" do
      fenced = "```\n[1, 2, 3]\n```"
      out = helper.ck_format_maybe_json(fenced)
      expect(out).to include('class="ck-json-number"')
      expect(out).to include("1")
    end

    it "still returns the raw input when a fenced block contains malformed JSON" do
      fenced = "```json\n{not valid\n```"
      expect(helper.ck_format_maybe_json(fenced)).to eq(fenced)
    end

    it "handles tabs and unterminated strings defensively when ck_highlight_json is called directly" do
      out = helper.ck_highlight_json("{\n\t\"k\":\t\"v\"\n}")
      expect(out).to include('class="ck-json-key"')

      unterminated = helper.ck_highlight_json('"unterminated')
      expect(unterminated).to include('class="ck-json-string"')
    end

    it "leaves stray characters through the :other branch when ck_highlight_json is given non-JSON noise" do
      out = helper.ck_highlight_json("@@@")
      expect(out).to eq("@@@")
    end
  end

  describe "#ck_field_aria and #ck_field_error" do
    let(:prompt) { build(:completion_kit_prompt, name: "", template: "x") }
    let(:form) { instance_double("ActionView::Helpers::FormBuilder", object: prompt) }

    it "returns an empty hash and nil when the field has no errors" do
      prompt.errors.clear
      expect(helper.ck_field_aria(form, :name)).to eq({})
      expect(helper.ck_field_error(form, :name)).to be_nil
    end

    it "returns aria-invalid + aria-describedby and an error paragraph when the field has errors" do
      prompt.errors.add(:name, "can't be blank")
      aria = helper.ck_field_aria(form, :name)
      expect(aria).to eq("aria-invalid" => "true", "aria-describedby" => "prompt_name_error")
      err = helper.ck_field_error(form, :name)
      expect(err).to include('id="prompt_name_error"', 'class="ck-field-error"')
      expect(err).to include("can&#39;t be blank")
    end
  end

end

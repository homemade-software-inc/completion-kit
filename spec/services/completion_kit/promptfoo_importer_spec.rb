require "rails_helper"

RSpec.describe CompletionKit::PromptfooImporter do
  def import(yaml)
    described_class.call(yaml)
  end

  let(:config) do
    <<~YAML
      providers:
        - openai:gpt-4o
        - anthropic:claude-3-5-sonnet
      prompts:
        - "Translate {{text}} into {{language}}."
        - file://big_prompt.txt
      tests:
        - vars:
            text: "Hello"
            language: "French"
        - vars:
            text: "Goodbye"
            language: "German"
      defaultTest:
        assert:
          - type: llm-rubric
            value: "Is the translation accurate and natural?"
          - type: contains
            value: "Bonjour"
          - type: is-json
          - type: regex
            value: "^[A-Z]"
          - type: javascript
            value: "output.length < 100"
    YAML
  end

  it "creates a prompt, a dataset, and judge plus check metrics" do
    result = import(config)

    expect(result.ok).to be(true)
    expect(result.prompts[:created]).to eq(["Imported prompt 1"])
    prompt = CompletionKit::Prompt.find_by(name: "Imported prompt 1")
    expect(prompt.template).to include("{{text}}", "{{language}}")
    expect(prompt.llm_model).to eq("gpt-4o")

    dataset = CompletionKit::Dataset.find_by(name: "Imported dataset")
    expect(dataset.headers).to match_array(%w[text language])
    expect(dataset.row_count).to eq(2)
  end

  it "maps llm-rubric to a judge metric and deterministic asserts to check metrics" do
    import(config)

    rubric = CompletionKit::Metric.find_by(metric_type: "llm_judge")
    expect(rubric.instruction).to include("accurate and natural")

    checks = CompletionKit::Metric.where(metric_type: "check")
    kinds = checks.map { |m| m.check_config["check_kind"] }
    expect(kinds).to include("contains", "valid_json", "regex")
    contains = checks.find { |m| m.check_config["check_kind"] == "contains" }
    expect(contains.check_config["value"]).to eq("Bonjour")
  end

  it "skips unsupported asserts and prompt files with a reason, never silently" do
    result = import(config)

    expect(result.metrics[:skipped].map { |s| s[:type] }).to include("javascript")
    expect(result.metrics[:skipped].first[:reason]).to be_present
    expect(result.prompts[:skipped].first[:value]).to include("file://")
    expect(result.prompts[:skipped].first[:reason]).to be_present
  end

  it "reports matched and unmatched providers" do
    create(:completion_kit_provider_credential, provider: "openai")

    result = import(config)

    expect(result.providers[:matched]).to include("openai:gpt-4o")
    expect(result.providers[:unmatched]).to include("anthropic:claude-3-5-sonnet")
  end

  it "honors icontains and not-contains case sensitivity" do
    yaml = <<~YAML
      defaultTest:
        assert:
          - type: icontains
            value: "ok"
          - type: not-contains
            value: "error"
    YAML
    import(yaml)

    icontains = CompletionKit::Metric.where(metric_type: "check").find { |m| m.check_config["value"] == "ok" }
    expect(icontains.check_config["check_kind"]).to eq("contains")
    expect(icontains.check_config["case_sensitive"]).to be(false)
    not_contains = CompletionKit::Metric.where(metric_type: "check").find { |m| m.check_config["check_kind"] == "not_contains" }
    expect(not_contains.check_config["value"]).to eq("error")
  end

  it "returns a failure result for unparseable YAML" do
    result = import("this: : : not valid")
    expect(result.ok).to be(false)
    expect(result.error).to include("parse")
  end

  it "returns a failure for a non-mapping top-level document" do
    result = import("- just\n- a\n- list")
    expect(result.ok).to be(false)
  end

  it "handles object-form providers and prompts and a colonless model" do
    yaml = <<~YAML
      providers:
        - id: customllm
      prompts:
        - raw: "Reply to {{q}}."
      tests:
        - vars: { q: "hi" }
    YAML
    result = import(yaml)

    expect(result.ok).to be(true)
    expect(CompletionKit::Prompt.find_by(name: "Imported prompt 1").template).to eq("Reply to {{q}}.")
    expect(CompletionKit::Prompt.first.llm_model).to eq("customllm")
  end

  it "skips the dataset when there are no tests with vars" do
    result = import("prompts:\n  - \"Hi\"\n")
    expect(result.dataset[:skipped]).to be_present
  end

  it "imports a template-keyed prompt object and skips a chat-array prompt" do
    yaml = <<~YAML
      prompts:
        - template: "Greet {{name}}."
        - - role: system
            content: "You are helpful."
      tests:
        - vars: { name: "Ada" }
    YAML
    result = import(yaml)

    expect(CompletionKit::Prompt.find_by(name: "Imported prompt 1").template).to eq("Greet {{name}}.")
    expect(result.prompts[:skipped].first[:reason]).to match(/unsupported prompt shape/)
  end

  it "tolerates a non-mapping test entry (a test-file reference string)" do
    yaml = <<~YAML
      tests:
        - file://cases.yaml
        - vars: { x: "1" }
          assert:
            - type: not-icontains
              value: "ERROR"
    YAML
    result = import(yaml)

    expect(result.ok).to be(true)
    expect(CompletionKit::Dataset.find_by(name: "Imported dataset").headers).to eq(["x"])
    nic = CompletionKit::Metric.where(metric_type: "check").first
    expect(nic.check_config["check_kind"]).to eq("not_contains")
    expect(nic.check_config["case_sensitive"]).to be(false)
  end

  it "skips an assert whose mapped check fails validation, with the validation reason" do
    yaml = <<~YAML
      defaultTest:
        assert:
          - type: regex
            value: "("
    YAML
    result = import(yaml)

    expect(CompletionKit::Metric.where(metric_type: "check")).to be_empty
    expect(result.metrics[:skipped].first[:reason]).to match(/regular expression/i)
  end

  it "deduplicates a metric name that collides with an existing metric" do
    create(:completion_kit_metric, name: "Valid JSON")
    result = import("defaultTest:\n  assert:\n    - type: is-json\n")

    expect(result.ok).to be(true)
    expect(result.metrics[:created].first[:name]).to eq("Valid JSON (2)")
  end

  it "deduplicates metric names when assert labels collide" do
    yaml = <<~YAML
      defaultTest:
        assert:
          - type: contains
            value: "x"
      tests:
        - vars: { a: "1" }
          assert:
            - type: contains
              value: "x"
        - vars: { a: "2" }
          assert:
            - type: equals
              value: "x"
    YAML
    result = import(yaml)
    expect(result.ok).to be(true)
    expect(CompletionKit::Metric.pluck(:name).uniq.length).to eq(CompletionKit::Metric.count)
  end
end

require "rails_helper"

RSpec.describe "CompletionKit model select error styling", type: :request do
  let(:css) { File.read(CompletionKit::Engine.root.join("app/assets/stylesheets/completion_kit/application.css")) }

  def rule_for(selector)
    rule = css.scan(/([^{}]+)\{([^}]*)\}/).find do |selectors, _|
      selectors.split(",").map(&:strip).include?(selector)
    end
    rule&.last
  end

  def errored_select(id)
    Nokogiri::HTML5(response.body).at_css(".ck-select-with-action > .field_with_errors > select##{id}")
  end

  it "lets the error wrapper take the flex space so the select keeps its width" do
    wrapper = rule_for(".ck-select-with-action > .field_with_errors")

    expect(wrapper).to match(/flex:\s*1;/)
    expect(wrapper).to match(/min-width:\s*0;/)
    expect(rule_for(".ck-select-with-action > .field_with_errors > .ck-input")).to match(/width:\s*100%;/)
  end

  it "gives an invalid field the same red border and focus ring as ck-input--error" do
    expect(rule_for('.ck-input[aria-invalid="true"]')).to eq(rule_for(".ck-input--error"))
    expect(rule_for('.ck-input[aria-invalid="true"]')).to match(/border-color:\s*var\(--ck-danger\);/)
    expect(rule_for('.ck-input[aria-invalid="true"]:focus')).to eq(rule_for(".ck-input--error:focus"))
  end

  it "tints an invalid select without dropping its arrow" do
    expect(rule_for(".ck-input--error")).to match(/background-color:/)
    expect(rule_for(".ck-input--error")).not_to match(/(^|[\s;])background:/)
  end

  it "wraps a rejected generation model in the styled error wrapper" do
    create(:completion_kit_model, provider: "openai", model_id: "gpt-4.1-mini", supports_generation: true)

    post "/completion_kit/prompts", params: { prompt: { name: "Summary", template: "Summarize {{content}}", llm_model: "ollama/llama3" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(errored_select("prompt_llm_model")["aria-invalid"]).to eq("true")
  end

  it "wraps a rejected judge model in the styled error wrapper" do
    prompt = create(:completion_kit_prompt)
    dataset = create(:completion_kit_dataset)

    post "/completion_kit/runs", params: { run: { prompt_id: prompt.id, dataset_id: dataset.id, judge_model: "ollama/llama3" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(errored_select("run_judge_model")["aria-invalid"]).to eq("true")
  end
end

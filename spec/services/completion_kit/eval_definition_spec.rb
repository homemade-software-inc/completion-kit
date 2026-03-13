require "rails_helper"

RSpec.describe CompletionKit::EvalDefinition do
  it "stores prompt name, dataset path, judge model, and metrics with thresholds" do
    defn = CompletionKit::EvalDefinition.new("support_summary")
    defn.prompt "support_summary"
    defn.dataset "evals/fixtures/support.csv"
    defn.judge_model "gpt-4.1"
    defn.metric :relevance, threshold: 7.0
    defn.metric :accuracy, threshold: 8.0

    expect(defn.eval_name).to eq("support_summary")
    expect(defn.prompt_name).to eq("support_summary")
    expect(defn.dataset_path).to eq("evals/fixtures/support.csv")
    expect(defn.judge_model_name).to eq("gpt-4.1")
    expect(defn.metrics).to eq([
      { key: :relevance, threshold: 7.0 },
      { key: :accuracy, threshold: 8.0 }
    ])
  end

  it "defaults judge_model from config" do
    defn = CompletionKit::EvalDefinition.new("test")
    defn.prompt "test"
    defn.dataset "test.csv"

    expect(defn.judge_model_name).to eq(CompletionKit.config.judge_model)
  end

  it "validates required fields" do
    defn = CompletionKit::EvalDefinition.new("incomplete")
    errors = defn.validation_errors

    expect(errors).to include("No prompt specified")
    expect(errors).to include("No dataset specified")
    expect(errors).to include("No metrics specified")
  end

  it "reports valid when all fields present" do
    defn = CompletionKit::EvalDefinition.new("complete")
    defn.prompt "p"
    defn.dataset "d.csv"
    defn.metric :x, threshold: 5.0

    expect(defn).to be_valid
  end
end

require "rails_helper"

RSpec.describe "CompletionKit.define_eval" do
  after { CompletionKit.clear_evals! }

  it "registers an eval definition" do
    CompletionKit.define_eval("my_eval") do |e|
      e.prompt "my_prompt"
      e.dataset "test.csv"
      e.metric :relevance, threshold: 7.0
    end

    expect(CompletionKit.registered_evals.size).to eq(1)
    expect(CompletionKit.registered_evals.first.eval_name).to eq("my_eval")
  end

  it "registers multiple evals" do
    CompletionKit.define_eval("eval_a") do |e|
      e.prompt "a"
      e.dataset "a.csv"
      e.metric :relevance, threshold: 7.0
    end

    CompletionKit.define_eval("eval_b") do |e|
      e.prompt "b"
      e.dataset "b.csv"
      e.metric :accuracy, threshold: 8.0
    end

    expect(CompletionKit.registered_evals.size).to eq(2)
  end

  it "clears the registry" do
    CompletionKit.define_eval("temp") do |e|
      e.prompt "temp"
      e.dataset "temp.csv"
      e.metric :x, threshold: 5.0
    end

    CompletionKit.clear_evals!
    expect(CompletionKit.registered_evals).to be_empty
  end
end

require "rails_helper"

RSpec.describe "Eval DSL end-to-end" do
  let!(:criteria) { create(:completion_kit_criteria) }
  let!(:relevance) { create(:completion_kit_metric, name: "Relevance", key: "relevance", criterias: [criteria]) }
  let!(:accuracy) { create(:completion_kit_metric, name: "Accuracy", key: "accuracy", criterias: [criteria]) }
  let!(:prompt) { create(:completion_kit_prompt, name: "e2e_test", current: true) }

  let(:csv_path) { Rails.root.join("tmp/e2e_eval.csv").to_s }

  before do
    FileUtils.mkdir_p(File.dirname(csv_path))
    File.write(csv_path, "content,audience,expected_output\nfirst row,devs,expected1\nsecond row,managers,expected2\n")
    mock_client = instance_double(CompletionKit::OpenAiClient, configured?: true, configuration_errors: [], generate_completion: "generated output")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(mock_client)
    allow_any_instance_of(CompletionKit::JudgeService).to receive(:evaluate).and_return({ score: 4.5, feedback: "Good work" })
  end

  after do
    CompletionKit.clear_evals!
    File.delete(csv_path) if File.exist?(csv_path)
  end

  it "defines an eval, runs it, and gets structured results" do
    CompletionKit.define_eval("e2e_test") do |e|
      e.prompt "e2e_test"
      e.dataset csv_path
      e.metric :relevance, threshold: 3.5
      e.metric :accuracy, threshold: 4.0
    end

    defn = CompletionKit.registered_evals.first
    runner = CompletionKit::EvalRunner.new(defn)
    result = runner.run

    expect(result[:passed]).to be true
    expect(result[:row_count]).to eq(2)
    expect(result[:metrics].size).to eq(2)

    run = CompletionKit::Run.find(result[:run_id])
    expect(run.name).to include("e2e_test")

    output = CompletionKit::EvalFormatter.format_results([result])
    expect(output).to include("2 rows")
    expect(output).to include("pass")
    expect(output).to include("1 passed, 0 failed")
  end
end

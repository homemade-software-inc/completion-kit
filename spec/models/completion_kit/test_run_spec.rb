require "rails_helper"

RSpec.describe CompletionKit::TestRun, type: :model do
  describe "validations and helpers" do
    it "defaults status to draft" do
      expect(build(:completion_kit_test_run, status: nil)).to be_valid
    end

    it "requires csv data" do
      test_run = build(:completion_kit_test_run, csv_data: nil)

      expect(test_run).not_to be_valid
      expect(test_run.errors[:csv_data]).to include("can't be blank")
    end

    it "processes csv data and resets cached rows when csv changes" do
      test_run = build(:completion_kit_test_run)

      expect(test_run.process_csv_data).to eq(true)

      test_run.csv_data = <<~CSV
        content,audience,expected_output
        "Updated","operators","A fresh summary"
      CSV

      expect(test_run.process_csv_data).to eq(true)
      expect(test_run.apply_variables_to_prompt("content" => "Updated", "audience" => "operators")).to include("Updated")
      expect(test_run.extract_expected_output("expected_output" => "Expected")).to eq("Expected")
    end

    it "returns false when the csv is invalid" do
      test_run = build(:completion_kit_test_run, csv_data: "not,csv")

      expect(test_run.process_csv_data).to eq(false)
    end
  end

  describe "#run_tests" do
    it "creates test results and marks the run completed" do
      test_run = create(:completion_kit_test_run)
      client = instance_double(CompletionKit::OpenAiClient, configured?: true)

      allow(client).to receive(:generate_completion).and_return("A developer-focused summary")
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

      expect { test_run.run_tests }.to change(CompletionKit::TestResult, :count).by(1)

      result = test_run.reload.test_results.first
      expect(test_run.status).to eq("completed")
      expect(result.output_text).to eq("A developer-focused summary")
      expect(result.expected_output).to eq("A developer-focused summary")
    end

    it "marks individual results failed when the client returns an error string" do
      test_run = create(:completion_kit_test_run)
      client = instance_double(CompletionKit::OpenAiClient, configured?: true, generate_completion: "Error: upstream")

      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

      expect(test_run.run_tests).to eq(true)
      expect(test_run.reload.test_results.first.status).to eq("failed")
    end

    it "fails cleanly when the provider is not configured" do
      test_run = create(:completion_kit_test_run)
      client = instance_double(CompletionKit::OpenAiClient, configured?: false, configuration_errors: ["OpenAI API key is not configured"])

      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

      expect(test_run.run_tests).to eq(false)
      expect(test_run.errors[:base]).to include("LLM API not properly configured: OpenAI API key is not configured")
      expect(test_run.reload.status).to eq("failed")
    end

    it "fails cleanly for an unpersisted run when the provider is not configured" do
      test_run = build(:completion_kit_test_run)
      client = instance_double(CompletionKit::OpenAiClient, configured?: false, configuration_errors: ["OpenAI API key is not configured"])

      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

      expect(test_run.run_tests).to eq(false)
      expect(test_run.errors[:base]).to include("LLM API not properly configured: OpenAI API key is not configured")
      expect(test_run.status).to eq("draft")
    end

    it "fails when csv processing produces no rows" do
      test_run = build(:completion_kit_test_run, csv_data: "")

      expect(test_run.run_tests).to eq(false)
    end

    it "captures unexpected exceptions and marks the run failed" do
      test_run = create(:completion_kit_test_run)
      client = instance_double(CompletionKit::OpenAiClient, configured?: true)

      allow(client).to receive(:generate_completion).and_raise(StandardError, "boom")
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

      expect(test_run.run_tests).to eq(false)
      expect(test_run.reload.status).to eq("failed")
      expect(test_run.errors[:base]).to include("Failed to run tests: boom")
    end

    it "captures client-construction exceptions for an unpersisted run before persistence" do
      test_run = build(:completion_kit_test_run)

      allow(CompletionKit::LlmClient).to receive(:for_model).and_raise(StandardError, "boom")

      expect(test_run.run_tests).to eq(false)
      expect(test_run.errors[:base]).to include("Failed to run tests: boom")
      expect(test_run.status).to eq("draft")
    end
  end

  describe "#evaluate_results" do
    it "marks the run evaluated when at least one result succeeds" do
      test_run = create(:completion_kit_test_run)
      result = create(:completion_kit_test_result, test_run: test_run)

      allow(result).to receive(:evaluate_quality).and_return(true)
      allow(test_run).to receive(:test_results).and_return([result])

      expect(test_run.evaluate_results).to eq(1)
      expect(test_run.reload.status).to eq("evaluated")
    end

    it "leaves the status alone when no result succeeds" do
      test_run = create(:completion_kit_test_run, status: "completed")
      result = create(:completion_kit_test_result, test_run: test_run)

      allow(result).to receive(:evaluate_quality).and_return(false)
      allow(test_run).to receive(:test_results).and_return([result])

      expect(test_run.evaluate_results).to eq(0)
      expect(test_run.reload.status).to eq("completed")
    end
  end
end

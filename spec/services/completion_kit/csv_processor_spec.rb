require "rails_helper"

RSpec.describe CompletionKit::CsvProcessor, type: :service do
  describe ".extract_variables" do
    it "extracts and normalizes template variables" do
      prompt = build(:completion_kit_prompt, template: "Hi {{ name }} and {{audience}}")

      expect(described_class.extract_variables(prompt)).to eq(%w[name audience])
    end

    it "returns an empty array when the prompt is nil" do
      expect(described_class.extract_variables(nil)).to eq([])
    end
  end

  describe ".process" do
    it "returns an empty array when csv data is blank" do
      test_run = build(:completion_kit_test_run, csv_data: nil)

      expect(described_class.process(test_run)).to eq([])
    end

    it "adds an error when the csv is malformed" do
      test_run = build(:completion_kit_test_run, csv_data: "\"unclosed")

      expect(described_class.process(test_run)).to eq([])
      expect(test_run.errors[:csv_data].first).to include("Invalid CSV format")
    end

    it "adds an error when no rows are present" do
      test_run = build(:completion_kit_test_run, csv_data: "content,audience,expected_output\n")

      expect(described_class.process(test_run)).to eq([])
      expect(test_run.errors[:csv_data]).to include("No data rows found in CSV")
    end

    it "adds an error when required headers are missing" do
      test_run = build(
        :completion_kit_test_run,
        csv_data: <<~CSV
          content
          "Only one column"
        CSV
      )

      expect(described_class.process(test_run)).to eq([])
      expect(test_run.errors[:csv_data]).to include("Missing required variables in CSV: audience")
    end

    it "returns parsed rows when the csv is valid" do
      test_run = build(:completion_kit_test_run)

      rows = described_class.process(test_run)

      expect(rows).to eq([{ "content" => "Release notes", "audience" => "developers", "expected_output" => "A developer-focused summary" }])
    end
  end

  describe ".apply_variables" do
    it "replaces variables even when the template contains spaces" do
      prompt = build(:completion_kit_prompt, template: "Hi {{ name }} for {{ audience }}")

      expect(described_class.apply_variables(prompt, "name" => "Ada", "audience" => "ops")).to eq("Hi Ada for ops")
    end
  end
end

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

  describe ".process_self" do
    it "returns an empty array when dataset is nil" do
      run = build(:completion_kit_run, dataset: nil)

      expect(described_class.process_self(run)).to eq([])
    end

    it "returns parsed rows from dataset csv_data" do
      dataset = build(:completion_kit_dataset)
      run = build(:completion_kit_run, dataset: dataset)

      rows = described_class.process_self(run)

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

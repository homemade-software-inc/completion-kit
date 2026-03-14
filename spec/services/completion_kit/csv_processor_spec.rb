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
    def run_double(csv_data:, prompt: nil)
      errors = ActiveModel::Errors.new(
        double("model", self_and_descendants_from_active_record_base: nil).tap { |m|
          allow(m).to receive(:human_attribute_name) { |a| a.to_s }
          allow(m).to receive(:lookup_ancestors_chain) { [] }
        }
      )
      dbl = double("run", csv_data: csv_data, prompt: prompt, errors: errors)
      dbl
    end

    it "returns empty array when csv_data is blank" do
      run = build(:completion_kit_run, dataset: nil)
      allow(run).to receive(:respond_to?).and_call_original
      csv_obj = Struct.new(:csv_data, :prompt, :errors).new(
        "",
        build(:completion_kit_prompt),
        ActiveModel::Errors.new(build(:completion_kit_run))
      )

      expect(described_class.process(csv_obj)).to eq([])
    end

    it "returns empty array and adds error when CSV has no data rows" do
      prompt = build(:completion_kit_prompt, template: "Hi")
      run = build(:completion_kit_run, prompt: prompt)
      csv_data_str = "header1,header2\n"

      obj = Struct.new(:csv_data, :prompt, :errors).new(csv_data_str, prompt, run.errors)

      result = described_class.process(obj)

      expect(result).to eq([])
      expect(obj.errors[:csv_data]).to include("No data rows found in CSV")
    end

    it "returns rows when CSV is valid and variables match" do
      prompt = build(:completion_kit_prompt, template: "Summarize {{content}} for {{audience}}")
      run = build(:completion_kit_run, prompt: prompt)
      obj = Struct.new(:csv_data, :prompt, :errors).new(
        "content,audience\nfoo,bar\n", prompt, run.errors
      )

      result = described_class.process(obj)

      expect(result).to eq([{ "content" => "foo", "audience" => "bar" }])
    end

    it "returns empty array and adds error when required variables are missing" do
      prompt = build(:completion_kit_prompt, template: "Hello {{name}}")
      run = build(:completion_kit_run, prompt: prompt)
      obj = Struct.new(:csv_data, :prompt, :errors).new(
        "content,audience\nfoo,bar\n", prompt, run.errors
      )

      result = described_class.process(obj)

      expect(result).to eq([])
      expect(obj.errors[:csv_data]).to include(match(/Missing required variables/))
    end

    it "returns empty array and adds error for malformed CSV" do
      prompt = build(:completion_kit_prompt, template: "Hi")
      run = build(:completion_kit_run, prompt: prompt)
      obj = Struct.new(:csv_data, :prompt, :errors).new(
        "col1,col2\n\"unclosed quote\n", prompt, run.errors
      )

      result = described_class.process(obj)

      expect(result).to eq([])
      expect(obj.errors[:csv_data]).to include(match(/Invalid CSV format/))
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

    it "returns empty array when dataset csv_data is malformed" do
      dataset = build(:completion_kit_dataset, csv_data: "col1,col2\n\"unclosed quote\n")
      run = build(:completion_kit_run, dataset: dataset)

      expect(described_class.process_self(run)).to eq([])
    end
  end

  describe ".apply_variables" do
    it "replaces variables even when the template contains spaces" do
      prompt = build(:completion_kit_prompt, template: "Hi {{ name }} for {{ audience }}")

      expect(described_class.apply_variables(prompt, "name" => "Ada", "audience" => "ops")).to eq("Hi Ada for ops")
    end
  end
end

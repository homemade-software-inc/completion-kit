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

    def variables_in(template)
      described_class.extract_variables(build(:completion_kit_prompt, template: template))
    end

    it "reads the same placeholders the {{name}} pattern always matched, edge cases included" do
      {
        "{{{a}}" => ["{a"],
        "{{{{a}}" => ["{{a"],
        "{{a}b}}" => [],
        "{{}}" => [],
        "{{a" => [],
        "no braces" => [],
        "{{a\n}}" => ["a"],
        "{{ a }} {{a}}" => ["a"],
        "{{a}}}{{b}}" => %w[a b],
        "{{a}{{b}}" => ["b"],
        "é {{ naïve }} ü {{x}}" => %w[naïve x]
      }.each do |template, expected|
        expect(variables_in(template)).to eq(expected), "for #{template.inspect}"
      end
    end

    it "agrees with the {{name}} pattern on every template in a seeded random sample" do
      random = Random.new(20_261_014)
      alphabet = ["{", "}", "a", "b", " ", "\n", "é"]
      2_000.times do
        template = Array.new(random.rand(1..24)) { alphabet[random.rand(alphabet.length)] }.join
        expected = template.scan(/\{\{([^}]+)\}\}/).flatten.map(&:strip).uniq
        expect(variables_in(template)).to eq(expected), "for #{template.inspect}"
      end
    end

    it "finds placeholders without the regex engine, so a huge template cannot trip a regex timeout" do
      prompt = build(:completion_kit_prompt, template: "{{ name }}#{"{" * 4_000_000}")
      original = Regexp.timeout
      Regexp.timeout = 0.001

      expect(described_class.extract_variables(prompt)).to eq(["name"])
    ensure
      Regexp.timeout = original
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

    [
      "C:\\\\Users\\\\share",
      "match \\0 here",
      "match \\& here",
      "C:\\Users\\1a",
      "\\'",
      "\\`",
      "last \\+ group",
      "named \\k<x> group"
    ].each do |value|
      it "inserts #{value.inspect} exactly as written" do
        prompt = build(:completion_kit_prompt, template: "A {{q}} B")

        expect(described_class.apply_variables(prompt, "q" => value)).to eq("A #{value} B")
      end
    end

    it "leaves a placeholder inside a value alone whatever the variable order" do
      prompt = build(:completion_kit_prompt, template: "A {{q}} B")

      expect(described_class.apply_variables(prompt, "q" => "{{r}}", "r" => "R")).to eq("A {{r}} B")
      expect(described_class.apply_variables(prompt, "r" => "R", "q" => "{{r}}")).to eq("A {{r}} B")
    end

    it "fills the template's own placeholder but not the copy inside another value" do
      prompt = build(:completion_kit_prompt, template: "A {{q}} B {{r}}")

      expect(described_class.apply_variables(prompt, "q" => "{{r}}", "r" => "R")).to eq("A {{r}} B R")
    end

    it "fills placeholders padded with whitespace or wrapped in a third brace" do
      prompt = build(:completion_kit_prompt, template: "{{  q }} {{{q}}}")

      expect(described_class.apply_variables(prompt, "q" => "x")).to eq("x {x}")
    end

    it "tells apart names where one is a prefix of another" do
      prompt = build(:completion_kit_prompt, template: "{{a}} {{ab}} {{a b}}")

      expect(described_class.apply_variables(prompt, "a" => "1", "ab" => "2", "a b" => "3")).to eq("1 2 3")
    end

    it "accepts symbol keys and renders nil as empty" do
      prompt = build(:completion_kit_prompt, template: "[{{name}}] [{{note}}]")

      expect(described_class.apply_variables(prompt, name: "Ada", note: nil)).to eq("[Ada] []")
    end

    it "leaves a placeholder with no matching variable unchanged" do
      prompt = build(:completion_kit_prompt, template: "Hi {{name}} from {{place}}")

      expect(described_class.apply_variables(prompt, "name" => "Ada")).to eq("Hi Ada from {{place}}")
    end

    it "returns a copy of the template when there are no variables" do
      prompt = build(:completion_kit_prompt, template: "Hi {{name}} {{}}")

      rendered = described_class.apply_variables(prompt, {})

      expect(rendered).to eq("Hi {{name}} {{}}")
      expect(rendered).not_to equal(prompt.template)
    end
  end
end

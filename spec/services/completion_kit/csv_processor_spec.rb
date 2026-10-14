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

    def fill(template, values)
      described_class.apply_variables(build(:completion_kit_prompt, template: template), values)
    end

    def pattern_fill(template, values)
      return template.dup if values.empty?

      names = values.keys.map { |name| Regexp.escape(name) }.join("|")
      template.gsub(/\{\{\s*(#{names})\s*\}\}/) { values[Regexp.last_match(1)].to_s }
    end

    def timed
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      [result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
    end

    it "matches a padded name only where the {{name}} pattern did, as a CSV header row like `name, city` gives" do
      values = { "name" => "Ada", " city" => "Paris", "zip " => "75" }

      expect(fill("{{name}} {{city}} {{ city }} {{zip}} {{ zip }}", values)).to eq("Ada {{city}} Paris {{zip}} 75")
    end

    it "fills the name the {{name}} pattern picked when several could match one placeholder" do
      expect(fill("{{ a }}", { " a " => "1", " a" => "2", "a" => "3" })).to eq("3")
      expect(fill("{{ a }}", { " a " => "1", "a " => "2" })).to eq("2")
      expect(fill("{{ a }}", { " a " => "1", " a" => "2" })).to eq("1")
      expect(fill("{{a}}}", { "a" => "1", "a}" => "2" })).to eq("1}")
      expect(fill("{{a}}}", { "a}" => "2", "a" => "1" })).to eq("2")
    end

    it "prefers the name with the least whitespace of its own before the text, then the earlier column, as the {{name}} pattern did" do
      expect(fill("{{  a  }}", { "  a" => "1", " a  " => "2" })).to eq("2")
      expect(fill("{{  a  }}", { " a " => "1", "a  " => "2", " a" => "3" })).to eq("2")
      expect(fill("{{  a  }}", { "  a  " => "1", " a" => "2", " a " => "3" })).to eq("2")
      expect(fill("{{ \ta\t }}", { " \ta\t " => "1", "\ta " => "2", "\ta\t" => "3" })).to eq("3")
      expect(fill("{{ \ta\t }}", { "\ta " => "1", "  a" => "2", " \ta\t " => "3" })).to eq("3")
    end

    it "prefers the blank name that starts latest, then the earlier column, as the {{name}} pattern did" do
      expect(fill("{{ \t}}", { " \t" => "A", " " => "B" })).to eq("A")
      expect(fill("{{ \t}}", { " " => "B", " \t" => "A" })).to eq("B")
      expect(fill("{{\t}} {{\t\t}}", { "\t\t" => "2", "\t" => "1" })).to eq("1 1")
    end

    it "fills a name padded with 30,000 spaces on each side fast" do
      padding = " " * 30_000

      rendered, elapsed = timed { fill("{{#{padding}z#{padding}}}", { "#{padding}z#{padding}" => "Z" }) }

      expect(rendered).to eq("Z")
      expect(elapsed).to be < 1
    end

    it "fills blank and brace-bearing names the way the {{name}} pattern did" do
      {
        ["{{}} {{  }}", { "" => "E" }] => "E E",
        ["{{ \t}} {{ }}", { " " => "S" }] => "S S",
        ["{{ \t}}", { " " => "S", "\t" => "T" }] => "T",
        ["{{a}}}", { "a}" => "1" }] => "1",
        ["{{{{x}}}}", { "{{x}}" => "1" }] => "1",
        ["{{ a}} }} {{b}}", { "a}} " => "1", "b" => "2" }] => "1 2",
        ["{{a}b}} {{a}}", { "a}b" => "1" }] => "1 {{a}}",
        ["{{a}}", { "a}}" => "1" }] => "{{a}}"
      }.each do |(template, values), expected|
        expect(fill(template, values)).to eq(expected), "for #{template.inspect} with #{values.inspect}"
      end
    end

    it "agrees with the {{name}} pattern on every template and name set in a seeded random sample" do
      random = Random.new(20_261_015)
      alphabet = ["{", "}", "}", "a", "b", " ", " ", "\t", "\n", "é"]
      spaces = [" ", "\t", "\n", "\v", "\f", "\r"]
      word = ->(longest) { Array.new(random.rand(0..longest)) { alphabet[random.rand(alphabet.length)] }.join }
      padding = -> { Array.new(random.rand(0..3)) { spaces[random.rand(spaces.length)] }.join }

      2_000.times do
        values = Array.new(random.rand(0..5)) { [word.call(5), "<#{random.rand(100)}>"] }.to_h
        names = values.keys
        template = Array.new(random.rand(1..6)) do
          name = names.empty? ? word.call(3) : names[random.rand(names.length)]
          case random.rand(4)
          when 0 then word.call(4)
          when 1 then "{{#{padding.call}#{name}#{padding.call}}}"
          when 2 then "{{#{padding.call}#{word.call(4)}#{padding.call}}}"
          else "#{"{" * random.rand(1..3)}#{name}#{"}" * random.rand(1..3)}"
          end
        end.join

        expect(fill(template, values)).to eq(pattern_fill(template, values)), "for #{template.inspect} with #{values.inspect}"
      end
    end

    context "with 2,000 columns" do
      let(:values) { (1..2_000).to_h { |index| ["column_#{index}", "value #{index}"] } }
      let(:placeholders) { values.keys.map { |name| "{{ #{name} }}" }.join(" ") }
      let(:expected) { values.values.join(" ") }

      it "fills every column fast, even with a long run of unclosed braces after them" do
        template = "#{placeholders}#{"{{" * 100_000}}}"

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        rendered = fill(template, values)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        expect(rendered).to eq("#{expected}#{"{{" * 100_000}}}")
        expect(elapsed).to be < 1
      end

      it "fills them without the regex engine, so a strict global regex timeout cannot fail the row" do
        prompt = build(:completion_kit_prompt, template: "#{placeholders}#{"{{ x " * 50_000}}}")
        original = Regexp.timeout
        Regexp.timeout = 0.001

        expect(described_class.apply_variables(prompt, values)).to eq("#{expected}#{"{{ x " * 50_000}}}")
      ensure
        Regexp.timeout = original
      end
    end
  end
end

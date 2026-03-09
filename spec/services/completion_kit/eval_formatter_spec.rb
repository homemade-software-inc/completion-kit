require "rails_helper"

RSpec.describe CompletionKit::EvalFormatter do
  describe ".format_results" do
    it "formats passing results" do
      results = [
        {
          eval_name: "support_summary",
          row_count: 24,
          metrics: [
            { key: :relevance, average: 8.2, threshold: 7.0, passed: true },
            { key: :accuracy, average: 8.7, threshold: 8.0, passed: true }
          ],
          passed: true
        }
      ]

      output = described_class.format_results(results)

      expect(output).to include("support_summary")
      expect(output).to include("24 rows")
      expect(output).to include("relevance")
      expect(output).to include("8.2")
      expect(output).to include("pass")
      expect(output).to include("1 passed, 0 failed")
    end

    it "formats failing results" do
      results = [
        {
          eval_name: "translation",
          row_count: 7,
          metrics: [
            { key: :relevance, average: 6.8, threshold: 7.0, passed: false },
            { key: :fluency, average: 9.1, threshold: 8.0, passed: true }
          ],
          passed: false
        }
      ]

      output = described_class.format_results(results)

      expect(output).to include("FAIL")
      expect(output).to include("0 passed, 1 failed")
      expect(output).to include("relevance")
      expect(output).to include("6.8")
    end

    it "formats error results" do
      results = [
        {
          eval_name: "broken",
          row_count: 0,
          metrics: [],
          passed: false,
          error: "Prompt 'missing' not found"
        }
      ]

      output = described_class.format_results(results)

      expect(output).to include("ERROR")
      expect(output).to include("missing")
    end
  end
end

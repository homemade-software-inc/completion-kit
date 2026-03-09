module CompletionKit
  class EvalRunner
    attr_reader :eval_definition, :test_run

    def initialize(eval_definition)
      @eval_definition = eval_definition
    end

    def run
      prompt = resolve_prompt
      return error_result("Prompt '#{eval_definition.prompt_name}' not found") unless prompt

      return error_result("Dataset '#{eval_definition.dataset_path}' not found") unless File.exist?(eval_definition.dataset_path)

      csv_data = File.read(eval_definition.dataset_path)

      metric_keys = eval_definition.metrics.map { |m| m[:key] }
      available_metrics = Metric.where(key: metric_keys.map(&:to_s)).index_by(&:key)
      missing = metric_keys.select { |k| available_metrics[k.to_s].nil? }
      if missing.any?
        available = Metric.pluck(:key).compact.join(", ")
        return error_result("Unknown metric keys: #{missing.join(", ")}. Available: #{available}")
      end

      @test_run = TestRun.create!(
        prompt: prompt,
        name: "eval: #{eval_definition.eval_name} (#{Time.current.strftime("%Y-%m-%d %H:%M")})",
        csv_data: csv_data,
        source: "eval_dsl",
        eval_name: eval_definition.eval_name
      )

      @test_run.run_tests
      @test_run.evaluate_results

      row_count = @test_run.test_results.count
      metric_results = eval_definition.metrics.map do |metric_def|
        assessments = TestResultMetricAssessment.joins(:test_result)
          .where(CompletionKit::TestResult.table_name => { test_run_id: @test_run.id })
          .where(metric_key_or_name_clause(metric_def[:key]))

        scores = assessments.where.not(ai_score: nil).pluck(:ai_score).map(&:to_f)
        average = scores.any? ? (scores.sum / scores.size).round(2) : 0.0

        {
          key: metric_def[:key],
          threshold: metric_def[:threshold],
          average: average,
          passed: average >= metric_def[:threshold]
        }
      end

      {
        eval_name: eval_definition.eval_name,
        row_count: row_count,
        metrics: metric_results,
        passed: metric_results.all? { |m| m[:passed] },
        test_run_id: @test_run.id
      }
    rescue StandardError => e
      error_result(e.message)
    end

    private

    def resolve_prompt
      Prompt.current_for(eval_definition.prompt_name)
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def metric_key_or_name_clause(key)
      metric = Metric.find_by(key: key.to_s)
      return { metric_id: metric.id } if metric
      { metric_name: key.to_s }
    end

    def error_result(message)
      {
        eval_name: eval_definition.eval_name,
        row_count: 0,
        metrics: [],
        passed: false,
        error: message
      }
    end
  end
end

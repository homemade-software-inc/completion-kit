require "json"

module CompletionKit
  class PromptImprovementValidator
    HELD_OUT_LIMIT = 30

    Candidate = Struct.new(:template)

    def initialize(run, candidate_template, generator: nil, judge: nil)
      @run = run
      @candidate = candidate_template
      @generator = generator || method(:generate)
      @judge = judge || method(:judge_score)
    end

    def call
      rows = held_out.filter_map do |response|
        new_text = @generator.call(response)
        next if new_text.blank?

        after = @judge.call(response, new_text)
        next if after.nil?

        row_for(response, after)
      rescue StandardError
        next
      end
      summarize(rows, @total.to_i, @total.to_i > HELD_OUT_LIMIT)
    end

    private

    def held_out
      scope = @run.responses
                  .where.not(response_text: [nil, ""])
                  .where.not(input_data: [nil, ""])
                  .where(id: Review.where.not(ai_score: nil).select(:response_id))
      @total = scope.count
      scope.order(:row_index).limit(HELD_OUT_LIMIT).to_a
    end

    def row_for(response, after)
      before = response.score
      {
        "response_id" => response.id,
        "before" => before.round(2),
        "after" => after.to_f.round(2),
        "delta" => (after.to_f - before).round(2)
      }
    end

    def summarize(rows, total, capped)
      improved = rows.count { |r| r["after"] > r["before"] }
      regressed = rows.count { |r| r["after"] < r["before"] }
      {
        "total" => total,
        "tested" => rows.size,
        "capped" => capped,
        "before_avg" => avg(rows.map { |r| r["before"] }),
        "after_avg" => avg(rows.map { |r| r["after"] }),
        "improved" => improved,
        "regressed" => regressed,
        "unchanged" => rows.size - improved - regressed,
        "rows" => rows
      }
    end

    def avg(values)
      return nil if values.empty?

      (values.sum / values.size).round(2)
    end

    def generate(response)
      rendered = CsvProcessor.apply_variables(Candidate.new(@candidate), parse_input(response.input_data))
      model = @run.prompt.llm_model
      client = LlmClient.for_model(model, ApiConfig.for_model(model))
      raise CompletionKit::ConfigurationError, client.configuration_errors.join(", ") unless client.configured?

      text = client.generate_completion(rendered, model: model, temperature: @run.temperature)
      raise StandardError, text if text.to_s.start_with?("Error:")

      text
    end

    def judge_score(response, new_text)
      config = ApiConfig.for_model(@run.judge_model).merge(judge_model: @run.judge_model)
      judge = JudgeService.new(config)
      scores = @run.metrics.select(&:llm_judge?).filter_map do |metric|
        judge.evaluate(
          new_text, response.expected_output, @candidate,
          criteria: metric.instruction.to_s,
          rubric_text: metric.display_rubric_text,
          input_data: response.input_data
        )[:score]
      end
      avg(scores)
    end

    def parse_input(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end
  end
end

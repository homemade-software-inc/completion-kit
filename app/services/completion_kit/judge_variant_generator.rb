module CompletionKit
  class JudgeVariantGenerator
    DEFAULT_VARIANT_COUNT = 3
    DEFAULT_TEMPERATURE = 0.4

    Variant = Struct.new(:reasoning, :instruction, keyword_init: true)

    def initialize(metric, count: DEFAULT_VARIANT_COUNT, model: nil)
      @metric = metric
      @count = count
      @model = model || CompletionKit.config.judge_model
    end

    def call
      client = LlmClient.for_model(@model, ApiConfig.for_model(@model))
      raw = client.generate_completion(build_meta_prompt, model: @model, max_tokens: 2500, temperature: DEFAULT_TEMPERATURE)
      parse(raw).first(@count)
    end

    def persist!(variants)
      JudgeVersion.where(metric_id: @metric.id, state: "draft", source: "suggestion").update_all(current: false)
      versions = variants.map do |variant|
        JudgeVersion.create!(
          metric: @metric,
          instruction: variant.instruction,
          rubric_bands: @metric.rubric_bands,
          state: "draft",
          source: "suggestion",
          current: false
        )
      end
      ActiveSupport::Notifications.instrument("completion_kit.judge_suggestion.generated",
                                              metric_id: @metric.id,
                                              count: versions.length,
                                              model: @model)
      versions
    end

    private

    def build_meta_prompt
      examples = JudgeCalibrationExamples.for(@metric)
      sections = []
      sections << "You are an expert evaluator. Rewrite a judge's grading instruction so it agrees better with humans on the cases below."
      sections << ""
      sections << "## Current instruction"
      sections << "```"
      sections << @metric.instruction.to_s
      sections << "```"
      sections << ""
      sections << "## Rubric (unchanged across variants — only rewrite the instruction)"
      sections << @metric.display_rubric_text
      sections << ""
      sections << "## Recent disagreements (judge vs human)"
      examples.each_with_index do |ex, i|
        sections << "### Case #{i + 1}"
        sections << "Input: #{ex[:input].to_s.truncate(200)}"
        sections << "Output: #{ex[:output].to_s.truncate(200)}"
        sections << "Judge said #{ex[:judge_score]}/5: #{ex[:judge_feedback].to_s.truncate(160)}"
        sections << "Human said #{ex[:human_score]}/5: #{ex[:human_note].to_s.truncate(160)}"
        sections << ""
      end
      sections << "## Task"
      sections << "Propose #{@count} alternative instructions. Each should be a focused rewrite — not a wholesale rewrite of the rubric. Aim to close the disagreement gap."
      sections << ""
      sections << "Respond in EXACTLY this format, repeated #{@count} times:"
      sections << ""
      sections << "VARIANT:"
      sections << "REASONING: <one sentence explaining what this variant changes>"
      sections << "INSTRUCTION:"
      sections << "<the rewritten instruction>"
      sections << "END_VARIANT"
      sections.join("\n")
    end

    def parse(text)
      blocks = text.to_s.scan(/VARIANT:(.*?)END_VARIANT/m).flatten
      blocks.filter_map do |raw|
        reasoning = raw[/REASONING:\s*(.*?)(?=INSTRUCTION:|\z)/m, 1].to_s.strip
        instruction = raw[/INSTRUCTION:\s*(.*)/m, 1].to_s.strip
        next if instruction.empty?
        Variant.new(reasoning: reasoning, instruction: instruction)
      end
    end
  end

  module JudgeCalibrationExamples
    module_function

    def for(metric, limit: 8)
      disagreements = Calibration.where(metric_id: metric.id, verdict: "disagree")
                                 .includes(response: :reviews)
                                 .order(created_at: :desc)
                                 .limit(limit)
      disagreements.map do |cal|
        review = cal.response.reviews.find { |r| r.metric_id == metric.id }
        {
          input: cal.response.input_data,
          output: cal.response.response_text,
          judge_score: review&.ai_score,
          judge_feedback: review&.ai_feedback,
          human_score: cal.corrected_score,
          human_note: cal.note
        }
      end
    end
  end
end

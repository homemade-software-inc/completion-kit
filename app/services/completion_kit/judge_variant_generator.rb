module CompletionKit
  class JudgeVariantGenerator
    DEFAULT_VARIANT_COUNT = 1
    MAX_VARIANT_COUNT = 3
    DEFAULT_TEMPERATURE = 0.4

    Variant = Struct.new(:reasoning, :instruction, :rubric_bands, keyword_init: true)

    def initialize(metric, count: DEFAULT_VARIANT_COUNT, model: nil)
      @metric = metric
      n = count.to_i
      @count = n < 1 ? DEFAULT_VARIANT_COUNT : [n, MAX_VARIANT_COUNT].min
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
          rubric_bands: variant.rubric_bands.presence || @metric.rubric_bands,
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
      disagreements = JudgeCalibrationExamples.disagreements_for(@metric)
      borderlines = JudgeCalibrationExamples.borderlines_for(@metric)
      sections = []
      sections << "You are an expert evaluator. The judge below is misaligned with humans. Propose #{@count == 1 ? "a single" : "#{@count}"} concrete rewrite that closes the gap."
      sections << ""
      sections << "## Current instruction"
      sections << "```"
      sections << @metric.instruction.to_s
      sections << "```"
      sections << ""
      sections << "## Current rubric (5 to 1)"
      sections << @metric.display_rubric_text
      sections << ""
      if disagreements.any?
        sections << "## Recent disagreements (judge vs human)"
        disagreements.each_with_index do |ex, i|
          sections << "### Case #{i + 1}"
          sections << "Input: #{ex[:input].to_s.truncate(200)}"
          sections << "Output: #{ex[:output].to_s.truncate(200)}"
          sections << "Judge said #{ex[:judge_score]}/5: #{ex[:judge_feedback].to_s.truncate(160)}"
          sections << "Human said #{ex[:human_score]}/5: #{ex[:human_note].to_s.truncate(160)}"
          sections << ""
        end
      end
      if borderlines.any?
        sections << "## Rubric-ambiguous cases (humans marked these borderline)"
        sections << "These are cases where a human said the rubric itself was unclear. If the rubric needs sharpening, rewrite it."
        borderlines.each_with_index do |ex, i|
          sections << "### Borderline #{i + 1}"
          sections << "Input: #{ex[:input].to_s.truncate(200)}"
          sections << "Output: #{ex[:output].to_s.truncate(200)}"
          sections << "Judge said #{ex[:judge_score]}/5: #{ex[:judge_feedback].to_s.truncate(160)}"
          sections << "Human note: #{ex[:human_note].to_s.truncate(200)}" if ex[:human_note].to_s.present?
          sections << ""
        end
      end
      sections << "## Task"
      sections << "Make one substantive change. Don't just reword. If the disagreements look like instruction problems, rewrite the instruction. If they look like rubric problems (overlapping bands, undefined edge cases), rewrite the rubric. Rewrite both if both are wrong."
      sections << ""
      sections << "Respond in EXACTLY this format, repeated #{@count} time#{@count == 1 ? "" : "s"}:"
      sections << ""
      sections << "VARIANT:"
      sections << "REASONING: <one short sentence: what changes and why>"
      sections << "INSTRUCTION:"
      sections << "<the rewritten instruction>"
      sections << "RUBRIC:                  # optional — omit this block if the rubric is unchanged"
      sections << "5: <description for 5 stars>"
      sections << "4: <description for 4 stars>"
      sections << "3: <description for 3 stars>"
      sections << "2: <description for 2 stars>"
      sections << "1: <description for 1 star>"
      sections << "END_VARIANT"
      sections.join("\n")
    end

    def parse(text)
      blocks = text.to_s.scan(/VARIANT:(.*?)END_VARIANT/m).flatten
      blocks.filter_map do |raw|
        reasoning = raw[/REASONING:\s*(.*?)(?=INSTRUCTION:|\z)/m, 1].to_s.strip
        instruction = raw[/INSTRUCTION:\s*(.*?)(?=RUBRIC:|\z)/m, 1].to_s.strip
        next if instruction.empty?
        rubric_block = raw[/RUBRIC:\s*(.*)/m, 1].to_s
        Variant.new(reasoning: reasoning, instruction: instruction, rubric_bands: parse_rubric(rubric_block))
      end
    end

    def parse_rubric(block)
      return nil if block.strip.empty?
      bands = block.scan(/^\s*([1-5])\s*[:\-]\s*(.+?)\s*$/).map do |stars, description|
        { "stars" => stars.to_i, "description" => description.strip }
      end
      return nil if bands.length != 5
      bands.sort_by { |b| -b["stars"] }
    end
  end

  module JudgeCalibrationExamples
    module_function

    def for(metric, limit: 8)
      disagreements_for(metric, limit: limit)
    end

    def disagreements_for(metric, limit: 8)
      calibrations_for(metric, verdict: "disagree", limit: limit)
    end

    def borderlines_for(metric, limit: 6)
      calibrations_for(metric, verdict: "borderline", limit: limit)
    end

    def calibrations_for(metric, verdict:, limit:)
      Calibration.where(metric_id: metric.id, verdict: verdict)
                 .includes(response: :reviews)
                 .order(created_at: :desc)
                 .limit(limit)
                 .map do |cal|
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

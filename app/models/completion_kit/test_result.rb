module CompletionKit
  class TestResult < ApplicationRecord
    belongs_to :test_run
    has_many :metric_assessments, class_name: "CompletionKit::TestResultMetricAssessment", dependent: :destroy

    delegate :prompt, to: :test_run

    validates :input_data, presence: true
    validates :output_text, presence: true
    validates :quality_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10, allow_nil: true }
    validates :human_score, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 10, allow_nil: true }
    validates :judge_feedback, presence: true, allow_nil: true
    validates :expected_output, presence: true, allow_nil: true

    def evaluate_quality
      return false if output_text.blank?

      evaluations = []

      transaction do
        retained_assessment_ids = []

        prompt.assessment_metrics.each do |metric|
          evaluation = JudgeService.new(judge_model: prompt.assessment_model).evaluate(
            output_text,
            expected_output,
            prompt.template,
            input_data: input_data,
            review_guidance: combined_review_guidance(metric),
            rubric_text: metric.rubric_text,
            human_examples: prompt.human_review_examples(metric: metric, excluding_test_result_id: id),
            test_run_id: test_run_id
          )

          assessment = find_or_initialize_metric_assessment(metric)
          assessment.assign_attributes(
            metric: metric.respond_to?(:persisted?) && metric.persisted? ? metric : nil,
            metric_name: metric.name,
            guidance_text: metric.guidance_text,
            rubric_text: metric.rubric_text,
            status: assessment.human_score.present? ? "reviewed" : "evaluated",
            ai_score: evaluation[:score],
            ai_feedback: evaluation[:feedback]
          )
          assessment.save!
          retained_assessment_ids << assessment.id
          evaluations << assessment
        end

        metric_assessments.where.not(id: retained_assessment_ids).destroy_all if retained_assessment_ids.any?
        refresh_aggregate_scores!(status: "evaluated")
      end

      evaluations.any?
    rescue StandardError => e
      update(
        status: "failed",
        quality_score: nil,
        judge_feedback: "Error during evaluation: #{e.message}"
      )
      false
    end

    def metric_assessments_for_review
      existing = metric_assessments.order(:id).to_a
      return existing if existing.any?

      prompt.assessment_metrics.map do |metric|
        metric_assessments.build(
          metric: metric.respond_to?(:persisted?) && metric.persisted? ? metric : nil,
          metric_name: metric.name,
          guidance_text: metric.guidance_text,
          rubric_text: metric.rubric_text
        )
      end
    end

    def apply_human_reviews!(assessment_attributes)
      transaction do
        Array(assessment_attributes).each do |attributes|
          attrs = attributes.to_h.stringify_keys
          next if attrs["human_score"].blank? && attrs["human_feedback"].blank? && attrs["human_reviewer_name"].blank?

          assessment = if attrs["id"].present?
                         metric_assessments.find(attrs["id"])
                       elsif attrs["metric_id"].present?
                         metric_assessments.find_or_initialize_by(metric_id: attrs["metric_id"])
                       else
                         metric_assessments.find_or_initialize_by(metric_name: attrs["metric_name"])
                       end

          assessment.metric_id ||= attrs["metric_id"].presence
          assessment.metric_name ||= attrs["metric_name"]
          assessment.guidance_text ||= attrs["guidance_text"].to_s
          assessment.rubric_text ||= attrs["rubric_text"].to_s
          assessment.apply_human_review!(
            reviewer_name: attrs["human_reviewer_name"],
            score: attrs["human_score"],
            feedback: attrs["human_feedback"]
          )
        end

        refresh_aggregate_scores!
      end
    end

    def quality_band
      return :pending if quality_score.nil?
      return :high if quality_score >= CompletionKit.config.high_quality_threshold
      return :medium if quality_score >= CompletionKit.config.medium_quality_threshold

      :low
    end

    def refresh_aggregate_scores!(status: self.status)
      ai_scores = metric_assessments.where.not(ai_score: nil).pluck(:ai_score).map(&:to_f)
      human_scores = metric_assessments.where.not(human_score: nil).pluck(:human_score).map(&:to_f)
      ai_feedback = metric_assessments.where.not(ai_feedback: [nil, ""]).map { |assessment| "#{assessment.metric_name}: #{assessment.ai_feedback}" }
      human_feedback = metric_assessments.where.not(human_feedback: [nil, ""]).map { |assessment| "#{assessment.metric_name}: #{assessment.human_feedback}" }

      update!(
        status: status,
        quality_score: ai_scores.any? ? (ai_scores.sum / ai_scores.length).round(2) : nil,
        judge_feedback: ai_feedback.presence&.join("\n\n"),
        human_score: human_scores.any? ? (human_scores.sum / human_scores.length).round(1) : nil,
        human_feedback: human_feedback.presence&.join("\n\n"),
        human_reviewer_name: metric_assessments.where.not(human_reviewer_name: [nil, ""]).pick(:human_reviewer_name),
        human_reviewed_at: metric_assessments.where.not(human_reviewed_at: nil).maximum(:human_reviewed_at)
      )
    end

    private

    def combined_review_guidance(metric)
      [prompt.effective_review_guidance, metric.guidance_text].reject(&:blank?).join("\n\n")
    end

    def find_or_initialize_metric_assessment(metric)
      if metric.respond_to?(:persisted?) && metric.persisted?
        metric_assessments.find_or_initialize_by(metric_id: metric.id)
      else
        metric_assessments.find_or_initialize_by(metric_name: metric.name)
      end
    end
  end
end

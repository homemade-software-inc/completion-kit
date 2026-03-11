module CompletionKit
  class Run < ApplicationRecord
    STATUSES = %w[pending generating judging completed failed].freeze

    belongs_to :prompt
    belongs_to :dataset, optional: true
    belongs_to :metric_group, optional: true
    has_many :responses, dependent: :destroy

    validates :name, presence: true
    validates :status, inclusion: { in: STATUSES }

    before_validation :set_default_status, on: :create
    before_validation :set_auto_name, on: :create

    def judge_configured?
      judge_model.present? && ApiConfig.valid_for_model?(judge_model)
    end

    def metrics
      metric_group&.ordered_metrics || []
    end

    def avg_score
      scores = responses.joins(:reviews).where.not(completion_kit_reviews: { ai_score: nil }).pluck("completion_kit_reviews.ai_score").map(&:to_f)
      return nil if scores.empty?

      (scores.sum / scores.length).round(2)
    end

    def generate_responses!
      rows = CsvProcessor.process_self(self)
      return false if rows.empty?

      client = LlmClient.for_model(prompt.llm_model, ApiConfig.for_model(prompt.llm_model))

      unless client.configured?
        errors.add(:base, "LLM API not configured: #{client.configuration_errors.join(', ')}")
        update_column(:status, "failed") if persisted?
        return false
      end

      transaction do
        update!(status: "generating")
        responses.delete_all

        rows.each do |row|
          output = client.generate_completion(CsvProcessor.apply_variables(prompt, row), model: prompt.llm_model)

          responses.create!(
            input_data: row.to_json,
            response_text: output,
            expected_output: row["expected_output"]
          )
        end

        if judge_configured?
          judge_responses!
        else
          update!(status: "completed")
        end
      end

      true
    rescue StandardError => e
      errors.add(:base, "Failed to generate responses: #{e.message}")
      update_column(:status, "failed") if persisted?
      false
    end

    def judge_responses!
      update!(status: "judging")

      judge = JudgeService.new(ApiConfig.for_model(judge_model).merge(judge_model: judge_model))

      responses.find_each do |response|
        metrics.each do |metric|
          evaluation = judge.evaluate(
            response.response_text,
            response.expected_output,
            prompt.template,
            criteria: metric.respond_to?(:criteria) ? metric.criteria.to_s : "",
            evaluation_steps: metric.respond_to?(:evaluation_steps) ? metric.evaluation_steps : nil,
            rubric_text: metric.respond_to?(:display_rubric_text) ? metric.display_rubric_text : nil
          )

          response.reviews.find_or_initialize_by(metric_id: metric.id).tap do |review|
            review.assign_attributes(
              metric_name: metric.name,
              criteria: metric.respond_to?(:criteria) ? metric.criteria.to_s : "",
              status: "evaluated",
              ai_score: evaluation[:score],
              ai_feedback: evaluation[:feedback]
            )
            review.save!
          end
        end
      end

      update!(status: "completed")
    rescue StandardError => e
      errors.add(:base, "Failed to judge responses: #{e.message}")
      update_column(:status, "failed") if persisted?
      false
    end

    private

    def set_default_status
      self.status ||= "pending"
    end

    def set_auto_name
      return if name.present?
      return unless prompt.present?

      version = prompt.version_number || 1
      timestamp = Time.current.strftime("%Y-%m-%d %H:%M")
      self.name = "#{prompt.name} v#{version} — #{timestamp}"
    end
  end
end

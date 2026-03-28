module CompletionKit
  class Run < ApplicationRecord
    include Turbo::Broadcastable

    STATUSES = %w[pending generating judging completed failed].freeze

    belongs_to :prompt
    belongs_to :dataset, optional: true
    has_many :responses, dependent: :destroy
    has_many :run_metrics, -> { order(:position) }, dependent: :destroy
    has_many :metrics, through: :run_metrics

    validates :name, presence: true
    validates :status, inclusion: { in: STATUSES }

    before_validation :set_default_status, on: :create
    before_validation :set_auto_name, on: :create

    def judge_configured?
      judge_model.present? && metrics.any? && ApiConfig.valid_for_model?(judge_model)
    end

    def avg_score
      all_reviews = responses.flat_map(&:reviews)
      scores = all_reviews.map(&:ai_score).compact.map(&:to_f)
      return nil if scores.empty?

      (scores.sum / scores.length).round(2)
    end

    def metric_averages
      all_reviews = responses.flat_map(&:reviews).select { |r| r.ai_score.present? }
      all_reviews.group_by(&:metric_name).map do |name, reviews|
        scores = reviews.map { |r| r.ai_score.to_f }
        { name: name, avg: (scores.sum / scores.length).round(1) }
      end
    end

    def generate_responses!
      rows = if dataset
               CsvProcessor.process_self(self)
             else
               [{}]
             end

      if rows.empty?
        errors.add(:base, "Dataset has no rows")
        return false
      end

      client = LlmClient.for_model(prompt.llm_model, ApiConfig.for_model(prompt.llm_model))

      unless client.configured?
        errors.add(:base, "LLM API not configured: #{client.configuration_errors.join(', ')}")
        update_column(:status, "failed") if persisted?
        return false
      end

      update!(status: "generating", progress_current: 0, progress_total: rows.length, error_message: nil)
      responses.destroy_all
      broadcast_ui

      rows.each_with_index do |row, index|
        input = row.empty? ? nil : row.to_json
        rendered = CsvProcessor.apply_variables(prompt, row)
        response_text = client.generate_completion(rendered, model: prompt.llm_model)

        resp = responses.create!(
          input_data: input,
          response_text: response_text,
          expected_output: row["expected_output"]
        )

        update_columns(progress_current: index + 1)
        broadcast_progress
        broadcast_response(resp)
      end

      if judge_configured?
        judge_responses!
      else
        update!(status: "completed")
        broadcast_ui
      end

      true
    rescue Faraday::Error => e
      update_columns(status: "failed", error_message: e.message)
      errors.add(:base, e.message)
      broadcast_ui
      false
    rescue StandardError => e
      update_columns(status: "failed", error_message: e.message) if persisted?
      errors.add(:base, e.message)
      broadcast_ui if persisted?
      false
    end

    def judge_responses!
      total_evaluations = responses.count * metrics.count
      update!(status: "judging", progress_current: 0, progress_total: total_evaluations, error_message: nil)
      broadcast_ui

      judge = JudgeService.new(ApiConfig.for_model(judge_model).merge(judge_model: judge_model))
      evaluation_count = 0

      responses.find_each do |response|
        metrics.each do |metric|
          evaluation = judge.evaluate(
            response.response_text,
            response.expected_output,
            prompt.template,
            criteria: metric.respond_to?(:instruction) ? metric.instruction.to_s : "",
            evaluation_steps: metric.respond_to?(:evaluation_steps) ? metric.evaluation_steps : nil,
            rubric_text: metric.respond_to?(:display_rubric_text) ? metric.display_rubric_text : nil
          )

          response.reviews.find_or_initialize_by(metric_id: metric.id).tap do |review|
            review.assign_attributes(
              metric_name: metric.name,
              instruction: metric.respond_to?(:instruction) ? metric.instruction.to_s : "",
              status: "evaluated",
              ai_score: evaluation[:score],
              ai_feedback: evaluation[:feedback]
            )
            review.save!
          end

          evaluation_count += 1
          update_columns(progress_current: evaluation_count)
          broadcast_progress
        end

        broadcast_response_update(response)
      end

      update!(status: "completed")
      broadcast_ui
      true
    rescue Faraday::Error => e
      update_columns(status: "failed", error_message: e.message)
      errors.add(:base, e.message)
      broadcast_ui
      false
    rescue StandardError => e
      update_columns(status: "failed", error_message: e.message) if persisted?
      errors.add(:base, e.message)
      broadcast_ui if persisted?
      false
    end

    def as_json(options = {})
      {
        id: id, name: name, status: status, prompt_id: prompt_id,
        dataset_id: dataset_id, judge_model: judge_model,
        created_at: created_at, updated_at: updated_at,
        responses_count: responses.count, avg_score: avg_score,
        progress_current: progress_current, progress_total: progress_total,
        error_message: error_message, metric_ids: metric_ids
      }
    end

    private

    def broadcast_ui
      broadcast_progress
      broadcast_status_header
      broadcast_actions
    end

    def render_engine_partial(partial, locals)
      CompletionKit::ApplicationController.render(
        partial: partial,
        locals: locals
      )
    end

    def broadcast_progress
      broadcast_replace_to(
        "completion_kit_run_#{id}",
        target: "run_progress",
        html: render_engine_partial("completion_kit/runs/progress", run: self)
      )
    end

    def broadcast_status_header
      broadcast_replace_to(
        "completion_kit_run_#{id}",
        target: "run_status_header",
        html: render_engine_partial("completion_kit/runs/status_header", run: self)
      )
    end

    def broadcast_actions
      broadcast_replace_to(
        "completion_kit_run_#{id}",
        target: "run_actions",
        html: render_engine_partial("completion_kit/runs/actions", run: self)
      )
    end

    def broadcast_response(response)
      broadcast_append_to(
        "completion_kit_run_#{id}",
        target: "run_responses",
        html: render_engine_partial("completion_kit/runs/response_row", run: self, response: response, index: responses.where("id <= ?", response.id).count)
      )
    end

    def broadcast_response_update(response)
      broadcast_replace_to(
        "completion_kit_run_#{id}",
        target: "response_#{response.id}",
        html: render_engine_partial("completion_kit/runs/response_row", run: self, response: response, index: responses.where("id <= ?", response.id).count)
      )
    end

    def set_default_status
      self.status ||= "pending"
    end

    def set_auto_name
      return if name.present?
      return unless prompt.present?

      count = Run.where(prompt_id: prompt_id).count + 1
      self.name = "#{prompt.name} — v#{prompt.version_number} ##{count}"
    end
  end
end

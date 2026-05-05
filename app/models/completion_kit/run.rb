module CompletionKit
  class Run < ApplicationRecord
    include Turbo::Broadcastable

    STATUSES = %w[pending running completed failed].freeze

    belongs_to :prompt
    belongs_to :dataset, optional: true
    has_many :responses, dependent: :destroy
    has_many :run_metrics, -> { order(:position) }, dependent: :destroy
    has_many :metrics, through: :run_metrics
    has_many :suggestions, dependent: :destroy

    validates :name, presence: true
    validates :status, inclusion: { in: STATUSES }

    before_validation :set_default_status, on: :create
    before_validation :set_auto_name, on: :create

    def mark_completed!
      update!(status: "completed")
      broadcast_ui
    end

    def outstanding_work_zero?
      return false if responses.where.not(status: Response::TERMINAL_STATUSES).exists?

      metric_ids = metrics.pluck(:id)
      return true if metric_ids.empty?

      succeeded_response_ids = responses.where(status: "succeeded").pluck(:id)
      expected_reviews = succeeded_response_ids.size * metric_ids.size
      return true if expected_reviews.zero?

      terminal_review_count = Review.where(
        response_id: succeeded_response_ids,
        metric_id: metric_ids,
        status: Review::TERMINAL_STATUSES
      ).count

      terminal_review_count >= expected_reviews
    end

    def judge_configured?
      judge_model.present? && metrics.any? && ApiConfig.valid_for_model?(judge_model)
    end

    def replace_metrics!(metric_ids)
      return unless metric_ids
      run_metrics.delete_all
      Array(metric_ids).reject(&:blank?).each_with_index do |metric_id, index|
        run_metrics.create!(metric_id: metric_id, position: index + 1)
      end
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

    def start!
      rows = if dataset
               CsvProcessor.process_self(self)
             else
               [{}]
             end

      return fail_with_summary!("Dataset has no rows") if rows.empty?

      client = LlmClient.for_model(prompt.llm_model, ApiConfig.for_model(prompt.llm_model))
      unless client.configured?
        return fail_with_summary!("LLM API not configured: #{client.configuration_errors.join(', ')}")
      end

      transaction do
        responses.destroy_all
        update!(
          status: "running",
          progress_current: 0,
          progress_total: rows.length,
          failure_summary: nil,
          error_message: nil
        )
        rows.each_with_index do |row, index|
          input = row.empty? ? nil : row.to_json
          response = responses.create!(
            status: "pending",
            row_index: index,
            input_data: input,
            expected_output: row["expected_output"]
          )
          GenerateRowJob.perform_later(id, response.id)
        end
      end

      broadcast_ui
      broadcast_clear_responses
      true
    end

    def generate_responses!
      start!
    end

    def progress_snapshot
      generated_done = responses.where(status: "succeeded").count
      generated_failed = responses.where(status: "failed").count
      generated_total = progress_total

      metric_count = metrics.count
      succeeded_count = generated_done
      judged_total = succeeded_count * metric_count
      judged_done = Review.joins(:response)
        .where(completion_kit_responses: { run_id: id }, status: "succeeded").count
      judged_failed = Review.joins(:response)
        .where(completion_kit_responses: { run_id: id }, status: "failed").count

      {
        generated_done: generated_done,
        generated_total: generated_total,
        generated_failed: generated_failed,
        judged_done: judged_done,
        judged_total: judged_total,
        judged_failed: judged_failed
      }
    end

    def as_json(options = {})
      {
        id: id, name: name, status: status, prompt_id: prompt_id,
        dataset_id: dataset_id, judge_model: judge_model, temperature: temperature,
        created_at: created_at, updated_at: updated_at,
        responses_count: responses.count, avg_score: avg_score,
        progress_current: progress_current, progress_total: progress_total,
        error_message: error_message, metric_ids: metric_ids
      }
    end

    private

    def fail_with_summary!(message)
      errors.add(:base, message)
      if persisted?
        update_columns(status: "failed", failure_summary: message, error_message: message)
        broadcast_ui
      end
      false
    end

    def broadcast_ui
      broadcast_progress
      broadcast_status_header
      broadcast_actions
      broadcast_sort_toolbar
    end

    def render_engine_partial(partial, locals)
      CompletionKit::ApplicationController.render(
        partial: partial,
        locals: locals
      )
    end

    def broadcast_progress
      reload
      broadcast_replace_to(
        "completion_kit_run_#{id}",
        target: "run_progress",
        html: render_engine_partial("completion_kit/runs/progress", run: self)
      )
      broadcast_status_header
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

    def broadcast_sort_toolbar
      broadcast_replace_to(
        "completion_kit_run_#{id}",
        target: "run_sort_toolbar",
        html: render_engine_partial("completion_kit/runs/sort_toolbar", run: self)
      )
    end

    def broadcast_clear_responses
      broadcast_replace_to(
        "completion_kit_run_#{id}",
        target: "run_responses",
        html: '<div id="run_responses"></div>'
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

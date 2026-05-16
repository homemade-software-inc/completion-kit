module CompletionKit
  class Run < ApplicationRecord
    include Turbo::Broadcastable
    include CompletionKit::Taggable

    STATUSES = %w[pending running completed failed].freeze

    belongs_to :prompt, optional: true
    belongs_to :dataset, optional: true
    has_many :responses, dependent: :destroy
    has_many :run_metrics, -> { order(:position) }, dependent: :destroy
    has_many :metrics, through: :run_metrics
    has_many :suggestions, dependent: :destroy
    has_many :dashboard_dismissals, as: :dismissable, dependent: :destroy
    has_many :calibrations, dependent: :destroy

    validates :name, presence: true
    validates :status, inclusion: { in: STATUSES }
    validate :dataset_supplies_prompt_variables
    validate :judge_only_run_supplies_output_column

    before_validation :set_default_status, on: :create
    before_validation :set_auto_name, on: :create

    # A judge-only run grades a pre-existing column on the dataset instead of
    # generating new outputs. No prompt is attached; the response text is read
    # from row[output_column]; no LLM generation happens.
    def judge_only?
      prompt.nil?
    end

    def missing_dataset_variables
      return [] unless prompt
      vars = prompt.variables
      return [] if vars.empty?
      return vars if dataset.nil?

      vars - dataset.headers
    end

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

      if judge_only?
        column = output_column.presence || "actual_output"
        return fail_with_summary!("Dataset has no \"#{column}\" column") unless dataset && dataset.headers.include?(column)
      else
        client = LlmClient.for_model(prompt.llm_model, ApiConfig.for_model(prompt.llm_model))
        unless client.configured?
          return fail_with_summary!("LLM API not configured: #{client.configuration_errors.join(', ')}")
        end
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
          attrs = {
            status: "pending",
            row_index: index,
            input_data: input,
            expected_output: row["expected_output"]
          }
          if judge_only?
            attrs[:status] = "succeeded"
            attrs[:response_text] = row[output_column.presence || "actual_output"].to_s
          end

          response = responses.create!(attrs)

          if judge_only?
            metrics.each { |m| JudgeReviewJob.perform_later(response.id, m.id) } if judge_configured?
          else
            GenerateRowJob.perform_later(id, response.id)
          end
        end

        RunCompletionCheckJob.perform_later(id) if judge_only?
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
      judged_total = metric_count > 0 ? generated_done : 0
      judged_done = 0
      judged_failed = 0

      if metric_count > 0 && judged_total > 0
        succeeded_response_ids = responses.where(status: "succeeded").pluck(:id)
        metric_ids = metrics.pluck(:id)
        review_counts = Review
          .where(response_id: succeeded_response_ids, metric_id: metric_ids)
          .group(:response_id, :status)
          .count
        succeeded_response_ids.each do |rid|
          ok = review_counts[[rid, "succeeded"]] || 0
          bad = review_counts[[rid, "failed"]] || 0
          next unless ok + bad == metric_count
          if bad > 0
            judged_failed += 1
          else
            judged_done += 1
          end
        end
      end

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
      snap = progress_snapshot
      {
        id: id, name: name, status: status, prompt_id: prompt_id,
        dataset_id: dataset_id, judge_model: judge_model, temperature: temperature,
        output_column: output_column,
        created_at: created_at, updated_at: updated_at,
        responses_count: responses.count, avg_score: avg_score,
        progress_current: snap[:generated_done],
        progress_total: snap[:generated_total],
        progress: {
          generated: { done: snap[:generated_done], total: snap[:generated_total], failed: snap[:generated_failed] },
          judged:    { done: snap[:judged_done],    total: snap[:judged_total],    failed: snap[:judged_failed] }
        },
        failed_response_ids: responses.where(status: "failed").pluck(:id),
        failure_summary: failure_summary,
        error_message: error_message,
        metric_ids: metric_ids,
        tags: tags.as_json
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
      CompletionKit::Engine.routes.url_helpers
      CompletionKit::ApplicationController.render(
        partial: partial,
        locals: locals
      )
    end

    def broadcast_progress
      reload
      broadcast_replace_to(
        "completion_kit_run_#{id}",
        target: "run_status_panel",
        html: render_engine_partial("completion_kit/runs/status_panel", run: self)
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
        html: '<tbody id="run_responses"></tbody>'
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

      if prompt.present?
        count = Run.where(prompt_id: prompt_id).count + 1
        self.name = "#{prompt.name} — v#{prompt.version_number} ##{count}"
      elsif dataset.present?
        count = Run.where(prompt_id: nil, dataset_id: dataset.id).count + 1
        self.name = "#{dataset.name} — judge-only ##{count}"
      end
    end

    def dataset_supplies_prompt_variables
      missing = missing_dataset_variables
      return if missing.empty?

      if dataset.nil?
        errors.add(:dataset_id, "is required: prompt uses #{missing.join(', ')}")
      else
        errors.add(:dataset_id, "is missing columns required by the prompt: #{missing.join(', ')}")
      end
    end

    def judge_only_run_supplies_output_column
      return if prompt.present?

      if dataset.nil?
        errors.add(:dataset_id, "is required for a judge-only run (no prompt)")
        return
      end

      column = output_column.presence || "actual_output"
      unless dataset.headers.include?(column)
        errors.add(:output_column, "\"#{column}\" is not a column on dataset \"#{dataset.name}\"")
      end
    end
  end
end

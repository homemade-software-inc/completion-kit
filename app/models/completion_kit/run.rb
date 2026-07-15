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

    validates :name, presence: true
    validates :status, inclusion: { in: STATUSES }
    validate :dataset_supplies_prompt_variables
    validate :judge_only_run_supplies_output_column
    validate :dataset_supplies_expected_column

    before_validation :set_default_status, on: :create
    before_validation :set_auto_name, on: :create
    after_create_commit :notify_host_of_creation
    after_update_commit :notify_host_of_start

    def self.display_scoped
      filter = CompletionKit.config.runs_display_scope
      filter ? all.instance_exec(&filter) : all
    end

    def self.visible_run_ids
      display_scoped.select(:id)
    end

    # A scoring-only run grades a pre-existing column on the dataset instead of
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

    def gradable_metric_ids
      ids = check_metrics.pluck(:id)
      ids += llm_metrics.pluck(:id) if judge_model.present?
      ids
    end

    def outstanding_work_zero?
      return false if responses.where.not(status: HasJobStatus::TERMINAL_STATUSES).exists?

      metric_ids = gradable_metric_ids
      return true if metric_ids.empty?

      succeeded_response_ids = responses.where(status: "succeeded").pluck(:id)
      expected_reviews = succeeded_response_ids.size * metric_ids.size
      return true if expected_reviews.zero?

      terminal_review_count = Review.where(
        response_id: succeeded_response_ids,
        metric_id: metric_ids,
        status: HasJobStatus::TERMINAL_STATUSES
      ).count

      terminal_review_count >= expected_reviews
    end

    def judge_configured?
      judge_model.present? && metrics.any? && ApiConfig.valid_for_model?(judge_model)
    end

    def llm_metrics
      metrics.where(metric_type: "llm_judge")
    end

    def check_metrics
      metrics.where(metric_type: "check")
    end

    def llm_judge_configured?
      judge_model.present? && llm_metrics.any? && ApiConfig.valid_for_model?(judge_model)
    end

    def gradable?
      llm_judge_configured? || check_metrics.any?
    end

    def judge_only_input_data_checks?
      return false unless judge_only?

      attached = run_metrics.filter_map(&:metric)
      return false if attached.empty?

      attached.all?(&:check?) && attached.all? { |m| m.check_config.to_h["target"] == "input_data" }
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
      responses.flat_map(&:reviews).group_by(&:metric_name).filter_map do |name, reviews|
        scored = reviews.select { |r| r.ai_score.present? }
        if scored.any?
          scores = scored.map { |r| r.ai_score.to_f }
          { name: name, avg: (scores.sum / scores.length).round(1) }
        else
          resolved = reviews.reject { |r| r.passed.nil? }
          next if resolved.empty?

          passed = resolved.count { |r| r.passed == true }
          { name: name, kind: "check", pass_rate: (passed.to_f / resolved.length).round(2) }
        end
      end
    end

    def check_pass_rate
      resolved = responses.flat_map(&:reviews).reject { |r| r.passed.nil? }
      return nil if resolved.empty?

      passed = resolved.count { |r| r.passed == true }
      (passed.to_f / resolved.length).round(2)
    end

    def stale_review_summary
      review_pairs = Review.where(response_id: response_ids)
                          .where.not(metric_id: nil)
                          .where.not(metric_version_id: nil)
                          .pluck(:metric_id, :metric_version_id, :metric_name)
      return {} if review_pairs.empty?

      metric_ids = review_pairs.map(&:first).uniq
      version_ids = review_pairs.map { |_, vid, _| vid }.uniq
      current_by_metric = MetricVersion.current.where(metric_id: metric_ids).pluck(:metric_id, :id, :version_number).each_with_object({}) do |(mid, vid, vnum), h|
        h[mid] = { id: vid, label: "v#{vnum}" }
      end
      label_by_version = MetricVersion.where(id: version_ids).pluck(:id, :version_number).each_with_object({}) { |(vid, vnum), h| h[vid] = "v#{vnum}" }

      summary = {}
      review_pairs.each do |metric_id, version_id, metric_name|
        current = current_by_metric[metric_id]
        next if current.nil?
        label = label_by_version[version_id]
        next if label.nil?
        next if label == current[:label]
        summary[metric_id] ||= { metric_name: metric_name, current_label: current[:label], stale_count: 0, scored_labels: [] }
        summary[metric_id][:stale_count] += 1
        summary[metric_id][:scored_labels] |= [label]
      end
      summary
    end

    def start!
      unless %w[pending failed].include?(status)
        return fail_with_summary!("Cannot start a run in state \"#{status}\". Use rerun to create a fresh copy, or retry_failures / regrade to work with the existing responses.")
      end

      rows = if dataset
               CsvProcessor.process_self(self)
             else
               [{}]
             end

      return fail_with_summary!("Dataset has no rows") if rows.empty?

      if judge_only?
        column = output_column.presence || "actual_output"
        unless judge_only_input_data_checks? || (dataset && dataset.headers.include?(column))
          return fail_with_summary!("Dataset has no \"#{column}\" column")
        end
      else
        client = LlmClient.for_model(prompt.llm_model, ApiConfig.for_model(prompt.llm_model))
        unless client.configured?
          return fail_with_summary!("LLM API not configured: #{client.configuration_errors.join(', ')}")
        end
      end

      begin
        transaction do
          responses.destroy_all
          update!(
            status: "running",
            progress_current: 0,
            progress_total: rows.length,
            failure_summary: nil,
            error_message: nil
          )

          now = Time.current
          out_col = output_column.presence || "actual_output"
          exp_col = expected_column.presence || "expected_output"
          judge = judge_only?
          has_output = judge && dataset && dataset.headers.include?(out_col)
          scope_defaults = Response.all.where_values_hash.symbolize_keys

          response_attrs = rows.each_with_index.map do |row, index|
            {
              run_id: id,
              status: judge ? "succeeded" : "pending",
              row_index: index,
              input_data: row.empty? ? nil : row.to_json,
              expected_output: row[exp_col],
              response_text: (judge && has_output ? row[out_col].to_s : nil),
              attempts: 0,
              created_at: now,
              updated_at: now
            }.merge(scope_defaults)
          end
          Response.insert_all(response_attrs)
          responses.reset

          response_ids = responses.order(:row_index).pluck(:id)
          if judge
            judge_metrics = llm_judge_configured? ? llm_metrics.to_a : []
            chk_metrics = check_metrics.to_a
            response_ids.each do |rid|
              judge_metrics.each { |m| JudgeReviewJob.perform_later(rid, m.id, id) }
              chk_metrics.each { |m| CheckReviewJob.perform_later(rid, m.id, id) }
            end
            RunCompletionCheckJob.perform_later(id)
          else
            response_ids.each { |rid| GenerateRowJob.perform_later(id, rid) }
          end
        end
      rescue ActiveRecord::RecordInvalid => e
        reload
        return fail_with_summary!(e.record.errors.full_messages.to_sentence)
      end

      safely_broadcast do
        broadcast_ui
        broadcast_clear_responses
      end
      true
    end

    def generate_responses!
      start!
    end

    def regrade!
      return false if metrics.empty? || !gradable?

      eligible_responses = responses.where(status: "succeeded")
      eligible_responses = eligible_responses.where.not(response_text: nil) unless judge_only_input_data_checks?
      response_ids = eligible_responses.pluck(:id)
      return false if response_ids.empty?

      transaction do
        Review.where(response_id: response_ids).update_all(
          status: "pending",
          attempts: 0,
          metric_version_id: nil,
          ai_score: nil,
          passed: nil,
          ai_feedback: nil,
          error_provider: nil,
          error_class: nil,
          error_status: nil,
          error_message: nil
        )
        update!(status: "running", failure_summary: nil, error_message: nil)

        response_ids.each do |rid|
          llm_metrics.each { |m| JudgeReviewJob.perform_later(rid, m.id, id) } if llm_judge_configured?
          check_metrics.each { |m| CheckReviewJob.perform_later(rid, m.id, id) }
        end
        RunCompletionCheckJob.perform_later(id)
      end

      broadcast_ui
      true
    end

    def progress_snapshot
      generated_done = responses.where(status: "succeeded").count
      generated_failed = responses.where(status: "failed").count
      generated_total = progress_total

      metric_ids = gradable_metric_ids
      metric_count = metric_ids.size
      judged_total = metric_count > 0 ? generated_done : 0
      judged_done = 0
      judged_failed = 0

      if metric_count > 0 && judged_total > 0
        succeeded_response_ids = responses.where(status: "succeeded").pluck(:id)
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
        expected_column: expected_column,
        created_at: created_at, updated_at: updated_at,
        responses_count: responses.count, avg_score: avg_score,
        check_pass_rate: check_pass_rate,
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

    def broadcast_ui
      broadcast_progress
      broadcast_status_header
      broadcast_actions
      broadcast_sort_toolbar
    end

    def broadcast_progress
      reload
      broadcast_replace_to(
        "completion_kit_run_#{id}",
        target: "run_status_panel",
        html: render_engine_partial("completion_kit/runs/status_panel", run: self)
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

    private

    def notify_host_of_creation
      CompletionKit.config.on_run_created&.call(self)
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { hook: "on_run_created", run_id: id })
    end

    def notify_host_of_start
      return unless saved_change_to_status? && status == "running"

      CompletionKit.config.on_run_started&.call(self)
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { hook: "on_run_started", run_id: id })
    end

    def fail_with_summary!(message)
      errors.add(:base, message)
      if persisted?
        update_columns(status: "failed", failure_summary: message, error_message: message)
        broadcast_ui
      end
      false
    end

    def render_engine_partial(partial, locals)
      CompletionKit::Engine.warm_routes!
      CompletionKit::ApplicationController.render(
        partial: partial,
        locals: locals
      )
    end

    def safely_broadcast
      yield
    rescue StandardError => e
      Rails.logger.error("[CompletionKit] run ##{id} broadcast failed: #{e.class}: #{e.message}")
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
        self.name = "#{dataset.name} scoring ##{count}"
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

    def dataset_supplies_expected_column
      return if expected_column.blank? || dataset.nil?

      unless dataset.headers.include?(expected_column)
        errors.add(:expected_column, "\"#{expected_column}\" is not a column on dataset \"#{dataset.name}\"")
      end
    end

    def judge_only_run_supplies_output_column
      return if prompt.present?

      if dataset.nil?
        errors.add(:dataset_id, "is required when scoring existing outputs (no prompt)")
        return
      end

      return if judge_only_input_data_checks?

      column = output_column.presence || "actual_output"
      unless dataset.headers.include?(column)
        errors.add(:output_column, "\"#{column}\" is not a column on dataset \"#{dataset.name}\"")
      end
    end
  end
end

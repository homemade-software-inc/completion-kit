module CompletionKit
  # One row per prompt per day, counting how often that prompt was fetched by a
  # consumer. Rolled up daily rather than stored per request so the table stays
  # bounded by (prompts x days) instead of growing with traffic.
  #
  # family_key is denormalised so a family's serving history survives deleting
  # an individual version, which prompt_id alone would not.
  class PromptServe < ApplicationRecord
    self.table_name = "completion_kit_prompt_serves"

    belongs_to :prompt, optional: true

    def self.record!(prompt)
      today = Date.current
      now = Time.current
      scope = where(prompt_id: prompt.id, served_on: today)

      return if scope.update_all(["serve_count = serve_count + 1, last_served_at = ?", now]).positive?

      create!(prompt_id: prompt.id, family_key: prompt.family_key, served_on: today,
              serve_count: 1, last_served_at: now)
    rescue ActiveRecord::RecordNotUnique
      scope.update_all(["serve_count = serve_count + 1, last_served_at = ?", now])
    end

    # Totals for the whole prompt family, so publishing a new version does not
    # reset the number a user is watching.
    def self.summary_for(prompt, windows: [7, 30])
      rows = where(family_key: prompt.family_key)
             .pluck(:served_on, :serve_count, :last_served_at)
      return { total: 0, last_served_at: nil }.merge(windows.index_with { 0 }) if rows.empty?

      summary = { total: rows.sum { |_, count, _| count },
                  last_served_at: rows.filter_map { |_, _, at| at }.max }
      windows.each_with_object(summary) do |days, acc|
        cutoff = Date.current - (days - 1)
        acc[days] = rows.sum { |on, count, _| on >= cutoff ? count : 0 }
      end
    end
  end
end

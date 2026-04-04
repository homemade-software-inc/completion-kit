module CompletionKit
  class Suggestion < ApplicationRecord
    belongs_to :run
    belongs_to :prompt

    validates :suggested_template, presence: true

    def as_json(options = {})
      {
        id: id, run_id: run_id, prompt_id: prompt_id,
        reasoning: reasoning, suggested_template: suggested_template,
        original_template: original_template, created_at: created_at
      }
    end
  end
end

module CompletionKit
  class Suggestion < ApplicationRecord
    belongs_to :run
    belongs_to :prompt

    validates :suggested_template, presence: true
  end
end

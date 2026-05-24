module CompletionKit
  class StarterMetricDismissal < ApplicationRecord
    validates :starter_key, presence: true, uniqueness: true
  end
end

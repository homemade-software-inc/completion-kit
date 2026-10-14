module CompletionKit
  class RunMetric < ApplicationRecord
    belongs_to :run
    belongs_to :metric, optional: false
  end
end

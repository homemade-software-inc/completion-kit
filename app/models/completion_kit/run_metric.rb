module CompletionKit
  class RunMetric < ApplicationRecord
    belongs_to :run
    belongs_to :metric
  end
end

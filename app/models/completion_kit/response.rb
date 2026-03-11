module CompletionKit
  class Response < ApplicationRecord
    belongs_to :run
    has_many :reviews, dependent: :destroy

    delegate :prompt, to: :run

    validates :input_data, presence: true
    validates :response_text, presence: true

    def score
      scores = reviews.where.not(ai_score: nil).pluck(:ai_score).map(&:to_f)
      return nil if scores.empty?

      (scores.sum / scores.length).round(2)
    end

    def reviewed?
      reviews.where.not(ai_score: nil).exists?
    end
  end
end

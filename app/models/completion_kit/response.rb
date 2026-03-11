module CompletionKit
  class Response < ApplicationRecord
    belongs_to :run
    has_many :reviews, dependent: :destroy

    delegate :prompt, to: :run

    validates :input_data, presence: true
    validates :response_text, presence: true

    def score
      scores = reviews.select { |r| r.ai_score.present? }.map { |r| r.ai_score.to_f }
      return nil if scores.empty?

      (scores.sum / scores.length).round(2)
    end

    def reviewed?
      reviews.any? { |r| r.ai_score.present? }
    end
  end
end

module CompletionKit
  class Response < ApplicationRecord
    belongs_to :run
    has_many :reviews, dependent: :destroy

    delegate :prompt, to: :run

    validates :response_text, presence: true

    def as_json(options = {})
      {
        id: id, run_id: run_id, input_data: input_data,
        response_text: response_text, expected_output: expected_output,
        created_at: created_at, score: score, reviewed: reviewed?,
        reviews: reviews.map(&:as_json)
      }
    end

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

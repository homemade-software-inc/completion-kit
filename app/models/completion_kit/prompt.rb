module CompletionKit
  class Prompt < ApplicationRecord
    has_many :test_runs, dependent: :destroy
    
    validates :name, presence: true
    validates :template, presence: true
    validates :llm_model, presence: true
  end
end

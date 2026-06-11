require "faraday"

module CompletionKit
  class PromptSuggestionJob < ApplicationJob
    queue_as :llm

    retry_on Faraday::TimeoutError, Faraday::ConnectionFailed, wait: :polynomially_longer, attempts: 5
    retry_on CompletionKit::RateLimitError, wait: :polynomially_longer, attempts: 5

    rescue_from(StandardError) do |error|
      Rails.error.report(error, handled: true, context: { job: self.class.name })
      if @suggestion
        @suggestion.update_columns(status: "failed")
        broadcast(@suggestion)
      end
    end

    def perform(suggestion_id)
      @suggestion = Suggestion.find_by(id: suggestion_id)
      return unless @suggestion

      run = @suggestion.run
      result = PromptImprovementService.new(run).suggest

      if result["suggested_template"].blank?
        @suggestion.update!(status: "failed")
        broadcast(@suggestion)
        return
      end

      summary = PromptImprovementValidator.new(run, result["suggested_template"]).call
      @suggestion.update!(
        reasoning: result["reasoning"],
        suggested_template: result["suggested_template"],
        validation_summary: summary,
        status: "ready"
      )
      broadcast(@suggestion)
    end

    private

    def broadcast(suggestion)
      html = CompletionKit::ApplicationController.render(
        partial: "completion_kit/suggestions/state",
        locals: { suggestion: suggestion, run: suggestion.run }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        "completion_kit_suggestion_#{suggestion.id}",
        target: "ck-suggestion-status-#{suggestion.id}",
        html: html
      )
    end
  end
end

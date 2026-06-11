module CompletionKit
  class SuggestionsController < ApplicationController
    before_action :set_suggestion

    def show
      @run = @suggestion.run
      @from = params[:from] == "run" ? "run" : "prompt"
    end

    def apply
      if @suggestion.applied_at?
        redirect_to suggestion_path(@suggestion), notice: "Suggestion already applied."
        return
      end

      unless @suggestion.ready?
        redirect_to suggestion_path(@suggestion), alert: "This suggestion isn't ready to apply yet."
        return
      end

      run = @suggestion.run
      new_prompt = run.prompt.clone_as_new_version(template: @suggestion.suggested_template)
      new_prompt.publish!
      @suggestion.update!(applied_at: Time.current)
      redirect_to prompt_path(new_prompt), notice: "Suggestion applied."
    end

    private

    def set_suggestion
      @suggestion = Suggestion.find(params[:id])
    end
  end
end

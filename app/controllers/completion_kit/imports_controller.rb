module CompletionKit
  class ImportsController < ApplicationController
    def new
    end

    def create
      content = uploaded_content

      if content.blank?
        flash.now[:alert] = "Paste or upload a promptfooconfig.yaml to import."
        return render :new, status: :unprocessable_entity
      end

      @result = PromptfooImporter.call(content)

      if @result.ok
        render :create
      else
        flash.now[:alert] = @result.error
        render :new, status: :unprocessable_entity
      end
    end

    private

    def uploaded_content
      file = params[:file]
      file.respond_to?(:read) ? file.read : params[:config]
    end
  end
end

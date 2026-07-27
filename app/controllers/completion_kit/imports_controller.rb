module CompletionKit
  class ImportsController < ApplicationController
    def new
    end

    def create
      if upload_too_large?(params[:file])
        flash.now[:alert] = "That file is too large. The limit is #{CompletionKit.config.max_upload_bytes / (1024 * 1024)} MB."
        return render :new, status: :payload_too_large
      end

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

    def upload_too_large?(file)
      file.respond_to?(:size) && file.size > CompletionKit.config.max_upload_bytes
    end
  end
end

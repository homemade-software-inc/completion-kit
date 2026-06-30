module CompletionKit
  module Api
    module V1
      class ImportsController < BaseController
        def promptfoo
          content = params[:config].presence || request.raw_post
          result = PromptfooImporter.call(content)

          if result.ok
            render json: import_summary(result), status: :created
          else
            render_error(result.error, status: :unprocessable_entity)
          end
        end

        private

        def import_summary(result)
          {
            prompts: result.prompts,
            dataset: result.dataset,
            metrics: result.metrics,
            providers: result.providers
          }
        end
      end
    end
  end
end

module CompletionKit
  module Api
    module V1
      class PromptsController < BaseController
        def index
          render json: Prompt.order(created_at: :desc)
        end
      end
    end
  end
end

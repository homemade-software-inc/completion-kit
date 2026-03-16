module CompletionKit
  module Api
    module V1
      class BaseController < ActionController::API
        before_action :authenticate_api!

        private

        def authenticate_api!
          token = CompletionKit.config.api_token
          unless token
            render json: {error: "API token not configured"}, status: :unauthorized
            return
          end

          provided = request.headers["Authorization"]&.match(/\ABearer (.+)\z/)&.[](1)
          unless provided && ActiveSupport::SecurityUtils.secure_compare(provided, token)
            render json: {error: "Unauthorized"}, status: :unauthorized
          end
        end

      end
    end
  end
end

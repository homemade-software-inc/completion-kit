module CompletionKit
  module Api
    module V1
      class BaseController < ActionController::API
        rate_limit to: CompletionKit.config.api_rate_limit, within: 1.minute,
                   with: -> { render_error("Rate limit exceeded", status: :too_many_requests) }
        before_action :authenticate_api!

        private

        def render_error(message, status:, details: nil)
          payload = { error: message }
          payload[:details] = details if details.present?
          render json: payload, status: status
        end

        def render_validation_errors(record, status: :unprocessable_entity)
          render_error("Validation failed", status: status, details: record.errors.as_json)
        end

        def authenticate_api!
          token = CompletionKit.config.api_token
          unless token
            render_error("API token not configured", status: :unauthorized)
            return
          end

          provided = request.headers["Authorization"]&.match(/\ABearer (.+)\z/)&.[](1)
          unless provided && ActiveSupport::SecurityUtils.secure_compare(provided, token)
            render_error("Unauthorized", status: :unauthorized)
          end
        end

        def not_found
          render_error("Record not found", status: :not_found)
        end

        PAGINATION_DEFAULT_LIMIT = 50
        PAGINATION_MAX_LIMIT = 500

        def paginate(scope)
          total = scope.count
          limit = (params[:limit].presence || PAGINATION_DEFAULT_LIMIT).to_i
          limit = PAGINATION_DEFAULT_LIMIT if limit <= 0
          limit = PAGINATION_MAX_LIMIT if limit > PAGINATION_MAX_LIMIT
          offset = params[:offset].to_i
          offset = 0 if offset < 0
          response.set_header("X-Total-Count", total.to_s)
          response.set_header("X-Limit", limit.to_s)
          response.set_header("X-Offset", offset.to_s)
          scope.limit(limit).offset(offset)
        end

        def filter_by_tags(scope)
          names = Array(params[:tag]).map(&:to_s).reject(&:blank?)
          return scope if names.empty?
          scope.joins(:tags).where(completion_kit_tags: { name: names }).distinct
        end

      end
    end
  end
end

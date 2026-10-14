module CompletionKit
  class McpController < Api::V1::BaseController
    PUBLIC_METHODS = %w[initialize notifications/initialized tools/list].freeze

    FOREIGN_KEY_MESSAGE = "This change references a record that does not exist or is still in use.".freeze
    TIMEOUT_MESSAGE = "The input was too large or too complex to process.".freeze

    skip_before_action :authenticate_api!, only: [:stream, :handle], raise: false

    def stream
      response.set_header("Allow", "POST, DELETE")
      head :method_not_allowed
    end

    def handle
      request_body = JSON.parse(request.body.read)
      unless request_body.is_a?(Hash)
        render json: jsonrpc_error(nil, -32600, "Invalid Request"), status: :bad_request
        return
      end
      return unless authorize_mcp_method(request_body["method"])

      if request_body["method"] == "initialize"
        result = McpDispatcher.initialize_session
        session_id = result.delete(:session_id)
        response.headers["Mcp-Session-Id"] = session_id
        render json: jsonrpc_response(request_body["id"], result)
        return
      end

      if request_body["method"] == "notifications/initialized"
        head :ok
        return
      end

      result = McpDispatcher.dispatch(request_body["method"], request_body["params"])
      render json: jsonrpc_response(request_body["id"], result)
    rescue JSON::ParserError
      render json: jsonrpc_error(nil, -32700, "Parse error"), status: :bad_request
    rescue McpDispatcher::MethodNotFound => e
      render json: jsonrpc_error(request_body.dig("id"), -32601, e.message), status: :ok
    rescue McpDispatcher::InvalidParams => e
      render json: jsonrpc_error(request_body.dig("id"), -32602, e.message), status: :ok
    rescue ActiveRecord::RecordNotFound => e
      render json: jsonrpc_error(request_body.dig("id"), -32602, not_found_message(e)), status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: jsonrpc_error(request_body.dig("id"), -32602, e.message), status: :ok
    rescue ActiveRecord::InvalidForeignKey => e
      Rails.error.report(e, handled: true, context: { controller: "CompletionKit::McpController" })
      render json: jsonrpc_error(request_body.dig("id"), -32602, FOREIGN_KEY_MESSAGE), status: :ok
    rescue Regexp::TimeoutError => e
      Rails.error.report(e, handled: true, context: { controller: "CompletionKit::McpController" })
      render json: jsonrpc_error(request_body.dig("id"), -32602, TIMEOUT_MESSAGE), status: :ok
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { controller: "CompletionKit::McpController" })
      render json: jsonrpc_error(request_body.dig("id"), -32603, "Internal error"), status: :ok
    end

    def destroy
      head :ok
    end

    private

    def authorize_mcp_method(method)
      return true if PUBLIC_METHODS.include?(method)
      authenticate_api!
      !performed?
    end

    def not_found_message(error)
      return "Record not found" unless error.model.present? && error.id.present?
      "#{error.model.demodulize.titleize} #{Array(error.id).join(", ")} not found"
    end

    def jsonrpc_response(id, result)
      {jsonrpc: "2.0", id: id, result: result}
    end

    def jsonrpc_error(id, code, message)
      {jsonrpc: "2.0", id: id, error: {code: code, message: message}}
    end
  end
end

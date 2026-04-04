module CompletionKit
  class McpController < Api::V1::BaseController
    def handle
      request_body = JSON.parse(request.body.read)

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

      session_id = request.headers["Mcp-Session-Id"]
      unless session_id && Rails.cache.exist?("mcp_session:#{session_id}")
        render json: jsonrpc_error(request_body["id"], -32000, "Session not initialized. Send initialize first."), status: :bad_request
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
      render json: jsonrpc_error(request_body&.dig("id"), -32602, e.message), status: :ok
    rescue ActiveRecord::RecordInvalid, ActiveRecord::InvalidForeignKey => e
      render json: jsonrpc_error(request_body&.dig("id"), -32602, e.message), status: :ok
    rescue StandardError => e
      render json: jsonrpc_error(request_body&.dig("id"), -32603, e.message), status: :ok
    end

    def destroy
      session_id = request.headers["Mcp-Session-Id"]
      Rails.cache.delete("mcp_session:#{session_id}") if session_id
      head :ok
    end

    private

    def jsonrpc_response(id, result)
      {jsonrpc: "2.0", id: id, result: result}
    end

    def jsonrpc_error(id, code, message)
      {jsonrpc: "2.0", id: id, error: {code: code, message: message}}
    end
  end
end

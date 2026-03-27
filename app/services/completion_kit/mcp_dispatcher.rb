module CompletionKit
  class McpDispatcher
    class MethodNotFound < StandardError; end
    class InvalidParams < StandardError; end

    PROTOCOL_VERSION = "2025-03-26"

    def self.initialize_session
      session_id = SecureRandom.uuid
      Rails.cache.write("mcp_session:#{session_id}", true, expires_in: 1.hour)
      {
        session_id: session_id,
        protocolVersion: PROTOCOL_VERSION,
        serverInfo: {name: "CompletionKit", version: CompletionKit::VERSION},
        capabilities: {tools: {listChanged: false}}
      }
    end

    def self.dispatch(method, params)
      case method
      when "tools/list"
        {tools: tool_definitions}
      when "tools/call"
        call_tool(params&.dig("name"), params&.dig("arguments") || {})
      else
        raise MethodNotFound, "Method not found: #{method}"
      end
    end

    def self.tool_definitions
      []
    end

    def self.call_tool(name, arguments)
      raise MethodNotFound, "Unknown tool: #{name}"
    end
  end
end

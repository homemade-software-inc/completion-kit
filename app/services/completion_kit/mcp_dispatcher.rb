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
      McpTools::Prompts.definitions +
        McpTools::Runs.definitions +
        McpTools::Responses.definitions +
        McpTools::Datasets.definitions +
        McpTools::Metrics.definitions +
        McpTools::Criteria.definitions +
        McpTools::ProviderCredentials.definitions
    end

    def self.call_tool(name, arguments)
      case name
      when /\Aprompts_/              then McpTools::Prompts.call(name, arguments)
      when /\Aruns_/                 then McpTools::Runs.call(name, arguments)
      when /\Aresponses_/            then McpTools::Responses.call(name, arguments)
      when /\Adatasets_/             then McpTools::Datasets.call(name, arguments)
      when /\Ametrics_/              then McpTools::Metrics.call(name, arguments)
      when /\Acriteria_/             then McpTools::Criteria.call(name, arguments)
      when /\Aprovider_credentials_/ then McpTools::ProviderCredentials.call(name, arguments)
      else raise MethodNotFound, "Unknown tool: #{name}"
      end
    end
  end
end

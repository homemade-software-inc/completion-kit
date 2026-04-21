module CompletionKit
  module McpTools
    module Base
      def definitions
        self::TOOLS.map { |name, config| {name: name, description: config[:description], inputSchema: config[:inputSchema]} }
      end

      def call(name, arguments)
        tool = self::TOOLS.fetch(name)
        send(tool[:handler], arguments)
      end

      def text_result(data)
        text = data.is_a?(String) ? data : data.to_json
        {content: [{type: "text", text: text}]}
      end

      def error_result(message)
        {content: [{type: "text", text: message}], isError: true}
      end
    end
  end
end

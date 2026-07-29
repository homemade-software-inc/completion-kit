module CompletionKit
  module McpTools
    module Base
      DEFAULT_PAGE_LIMIT = 50
      MAX_PAGE_LIMIT = 500

      def page_bounds(args)
        limit = args["limit"].to_i
        limit = DEFAULT_PAGE_LIMIT if limit <= 0
        limit = MAX_PAGE_LIMIT if limit > MAX_PAGE_LIMIT
        offset = args["offset"].to_i
        offset = 0 if offset < 0
        [limit, offset]
      end

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

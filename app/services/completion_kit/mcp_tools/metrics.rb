module CompletionKit
  module McpTools
    module Metrics
      TOOLS = {
        "metrics_list" => {
          description: "List all metrics",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "metrics_get" => {
          description: "Get a metric by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "metrics_create" => {
          description: "Create a metric with evaluation criteria",
          inputSchema: {
            type: "object",
            properties: {
              name: {type: "string"}, instruction: {type: "string"},
              evaluation_steps: {type: "array", items: {type: "string"}},
              rubric_bands: {type: "array", items: {type: "object", properties: {stars: {type: "integer"}, description: {type: "string"}}}}
            },
            required: ["name"]
          },
          handler: :create
        },
        "metrics_update" => {
          description: "Update a metric",
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, name: {type: "string"}, instruction: {type: "string"},
              evaluation_steps: {type: "array", items: {type: "string"}},
              rubric_bands: {type: "array", items: {type: "object", properties: {stars: {type: "integer"}, description: {type: "string"}}}}
            },
            required: ["id"]
          },
          handler: :update
        },
        "metrics_delete" => {
          description: "Delete a metric",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        }
      }.freeze

      def self.definitions
        TOOLS.map { |name, config| {name: name, description: config[:description], inputSchema: config[:inputSchema]} }
      end

      def self.call(name, arguments)
        tool = TOOLS.fetch(name)
        send(tool[:handler], arguments)
      end

      def self.list(_args)
        text_result(Metric.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(Metric.find(args["id"]).as_json)
      end

      def self.create(args)
        metric = Metric.new(args.slice("name", "instruction", "evaluation_steps", "rubric_bands"))
        if metric.save
          text_result(metric.as_json)
        else
          error_result(metric.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        metric = Metric.find(args["id"])
        if metric.update(args.except("id").slice("name", "instruction", "evaluation_steps", "rubric_bands"))
          text_result(metric.as_json)
        else
          error_result(metric.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        Metric.find(args["id"]).destroy!
        text_result("Metric #{args["id"]} deleted")
      end

      def self.text_result(data)
        text = data.is_a?(String) ? data : data.to_json
        {content: [{type: "text", text: text}]}
      end

      def self.error_result(message)
        {content: [{type: "text", text: message}], isError: true}
      end
    end
  end
end

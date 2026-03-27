module CompletionKit
  module McpTools
    module Criteria
      TOOLS = {
        "criteria_list" => {
          description: "List all criteria",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "criteria_get" => {
          description: "Get a criteria by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "criteria_create" => {
          description: "Create a criteria grouping metrics",
          inputSchema: {
            type: "object",
            properties: {
              name: {type: "string"}, description: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}}
            },
            required: ["name"]
          },
          handler: :create
        },
        "criteria_update" => {
          description: "Update a criteria",
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, name: {type: "string"}, description: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}}
            },
            required: ["id"]
          },
          handler: :update
        },
        "criteria_delete" => {
          description: "Delete a criteria",
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
        text_result(CompletionKit::Criteria.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(CompletionKit::Criteria.find(args["id"]).as_json)
      end

      def self.create(args)
        criteria = CompletionKit::Criteria.new(args.slice("name", "description"))
        if criteria.save
          replace_metric_memberships(criteria, args["metric_ids"])
          text_result(criteria.reload.as_json)
        else
          error_result(criteria.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        criteria = CompletionKit::Criteria.find(args["id"])
        if criteria.update(args.except("id", "metric_ids").slice("name", "description"))
          replace_metric_memberships(criteria, args["metric_ids"]) if args.key?("metric_ids")
          text_result(criteria.reload.as_json)
        else
          error_result(criteria.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        CompletionKit::Criteria.find(args["id"]).destroy!
        text_result("Criteria #{args["id"]} deleted")
      end

      def self.text_result(data)
        text = data.is_a?(String) ? data : data.to_json
        {content: [{type: "text", text: text}]}
      end

      def self.error_result(message)
        {content: [{type: "text", text: message}], isError: true}
      end

      def self.replace_metric_memberships(criteria, metric_ids)
        return unless metric_ids
        criteria.criteria_memberships.delete_all
        Array(metric_ids).reject(&:blank?).each_with_index do |metric_id, index|
          criteria.criteria_memberships.create!(metric_id: metric_id, position: index + 1)
        end
      end
    end
  end
end

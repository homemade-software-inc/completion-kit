module CompletionKit
  module McpTools
    module MetricGroups
      extend Base

      TOOLS = {
        "metric_groups_list" => {
          description: "List all metric groups",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "metric_groups_get" => {
          description: "Get a metric group by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "metric_groups_create" => {
          description: "Create a metric group",
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
        "metric_groups_update" => {
          description: "Update a metric group",
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
        "metric_groups_delete" => {
          description: "Delete a metric group",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        }
      }.freeze

      def self.list(_args)
        text_result(CompletionKit::MetricGroup.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(CompletionKit::MetricGroup.find(args["id"]).as_json)
      end

      def self.create(args)
        metric_group = CompletionKit::MetricGroup.new(args.slice("name", "description"))
        if metric_group.save
          replace_metric_memberships(metric_group, args["metric_ids"])
          text_result(metric_group.reload.as_json)
        else
          error_result(metric_group.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        metric_group = CompletionKit::MetricGroup.find(args["id"])
        if metric_group.update(args.except("id", "metric_ids").slice("name", "description"))
          replace_metric_memberships(metric_group, args["metric_ids"]) if args.key?("metric_ids")
          text_result(metric_group.reload.as_json)
        else
          error_result(metric_group.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        CompletionKit::MetricGroup.find(args["id"]).destroy!
        text_result("Metric group #{args["id"]} deleted")
      end

      def self.replace_metric_memberships(metric_group, metric_ids)
        return unless metric_ids
        metric_group.metric_group_memberships.delete_all
        Array(metric_ids).reject(&:blank?).each_with_index do |metric_id, index|
          metric_group.metric_group_memberships.create!(metric_id: metric_id, position: index + 1)
        end
      end
    end
  end
end

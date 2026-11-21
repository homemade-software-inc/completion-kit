module CompletionKit
  module McpTools
    module MetricGroups
      extend Base

      TOOLS = {
        "metric_groups_list" => {
          description: "List every metric group in your workspace, newest first. A metric group is a saved, ordered set of metrics that you can attach to a run in one step, so runs are scored the same way each time. Returns each group's id, name, description, metric_ids, tags and timestamps. The full list comes back with no paging. Use it to find a metric_group_id for runs_create or runs_update.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "metric_groups_get" => {
          description: "Get one metric group by id. Returns its id, name, description, the ids of its metrics in order, tags and timestamps. Use metrics_get on each id to see how each metric scores AI responses.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "metric_groups_create" => {
          description: "Create a metric group: a named, ordered set of metrics that you can attach to a run in one step with metric_group_id, so every run of a prompt is scored the same way. Send name, and optionally description, metric_ids in the order you want them and tag_names (any new tags are created). Each id must be a metric in this workspace, or the whole call fails. A run copies the group's metrics when you attach the group, so later changes to the group don't reach that run. Returns the saved group.",
          annotations: Base::ADDITIVE,
          inputSchema: {
            type: "object",
            properties: {
              name: {type: "string"}, description: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}},
              tag_names: {type: "array", items: {type: "string"}}
            },
            required: ["name"]
          },
          handler: :create
        },
        "metric_groups_update" => {
          description: "Change a metric group's name, description, metrics or tags. This overwrites the group in place. metric_ids replaces the group's whole metric list in the order given, and an empty list removes every metric. Each id must be a metric in this workspace. Leave metric_ids out to keep the current list. tag_names replaces the whole tag set. Runs already created keep the metrics they had. Returns the updated group.",
          annotations: Base::DESTRUCTIVE,
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, name: {type: "string"}, description: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}},
              tag_names: {type: "array", items: {type: "string"}}
            },
            required: ["id"]
          },
          handler: :update
        },
        "metric_groups_delete" => {
          description: "Permanently delete a metric group. Its tags are unlinked, though the tags themselves stay. The metrics in it, and any runs scored with it, stay as they are. This cannot be undone. Returns a confirmation message.",
          annotations: Base::DESTRUCTIVE,
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
        metric_group = CompletionKit::MetricGroup.new(args.slice("name", "description").merge("selected_metric_ids" => args["metric_ids"]))
        metric_group.tag_names = args["tag_names"] if args.key?("tag_names")
        if metric_group.save
          text_result(metric_group.reload.as_json)
        else
          error_result(metric_group.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        metric_group = CompletionKit::MetricGroup.find(args["id"])
        if metric_group.update(args.slice("name", "description").merge("selected_metric_ids" => args["metric_ids"]))
          metric_group.update!(tag_names: args["tag_names"]) if args.key?("tag_names")
          text_result(metric_group.reload.as_json)
        else
          error_result(metric_group.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        CompletionKit::MetricGroup.find(args["id"]).destroy!
        text_result("Metric group #{args["id"]} deleted")
      end
    end
  end
end

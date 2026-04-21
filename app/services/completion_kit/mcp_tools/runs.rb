module CompletionKit
  module McpTools
    module Runs
      extend Base

      TOOLS = {
        "runs_list" => {
          description: "List all runs",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "runs_get" => {
          description: "Get a run by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "runs_create" => {
          description: "Create a run",
          inputSchema: {
            type: "object",
            properties: {
              name: {type: "string"}, prompt_id: {type: "integer"},
              dataset_id: {type: "integer"}, judge_model: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}}
            },
            required: ["name", "prompt_id"]
          },
          handler: :create
        },
        "runs_update" => {
          description: "Update a run",
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, name: {type: "string"},
              dataset_id: {type: "integer"}, judge_model: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}}
            },
            required: ["id"]
          },
          handler: :update
        },
        "runs_delete" => {
          description: "Delete a run",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        },
        "runs_generate" => {
          description: "Generate responses for a run using its prompt and dataset",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :generate
        },
        "runs_judge" => {
          description: "Judge responses for a run using configured metrics",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :judge
        }
      }.freeze

      def self.list(_args)
        text_result(Run.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(Run.find(args["id"]).as_json)
      end

      def self.create(args)
        run = Run.new(args.slice("name", "prompt_id", "dataset_id", "judge_model"))
        if run.save
          replace_run_metrics(run, args["metric_ids"])
          text_result(run.reload.as_json)
        else
          error_result(run.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        run = Run.find(args["id"])
        if run.update(args.except("id", "metric_ids").slice("name", "dataset_id", "judge_model"))
          replace_run_metrics(run, args["metric_ids"]) if args.key?("metric_ids")
          text_result(run.reload.as_json)
        else
          error_result(run.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        Run.find(args["id"]).destroy!
        text_result("Run #{args["id"]} deleted")
      end

      def self.generate(args)
        run = Run.find(args["id"])
        GenerateJob.perform_later(run.id)
        text_result(run.reload.as_json)
      end

      def self.judge(args)
        run = Run.find(args["id"])
        JudgeJob.perform_later(run.id)
        text_result(run.reload.as_json)
      end

      def self.replace_run_metrics(run, metric_ids)
        return unless metric_ids
        run.run_metrics.delete_all
        Array(metric_ids).reject(&:blank?).each_with_index do |metric_id, index|
          run.run_metrics.create!(metric_id: metric_id, position: index + 1)
        end
      end
    end
  end
end

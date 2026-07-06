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
          description: "Create a run. Omit prompt_id and provide output_column to score existing outputs by grading a pre-existing dataset column instead of generating new ones.",
          inputSchema: {
            type: "object",
            properties: {
              name: {type: "string"}, prompt_id: {type: "integer"},
              dataset_id: {type: "integer"}, judge_model: {type: "string"},
              output_column: {type: "string", description: "Dataset column to grade when prompt_id is omitted; defaults to \"actual_output\"."},
              expected_column: {type: "string", description: "Dataset column holding each row's answer key / ground truth, graded by checks with compare_to \"expected\" and passed to the judge; defaults to \"expected_output\"."},
              metric_ids: {type: "array", items: {type: "integer"}},
              tag_names: {type: "array", items: {type: "string"}}
            },
            required: ["name"]
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
              output_column: {type: "string"},
              expected_column: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}},
              tag_names: {type: "array", items: {type: "string"}}
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
          description: "Start a run. Required for every run, including score-only runs (no prompt): generates responses with the prompt when there is one, otherwise copies the graded dataset column and grades it.",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :generate
        }
      }.freeze

      def self.list(_args)
        text_result(Run.display_scoped.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(Run.find(args["id"]).as_json)
      end

      def self.create(args)
        run = Run.new(args.slice("name", "prompt_id", "dataset_id", "judge_model", "output_column", "expected_column"))
        if run.save
          run.replace_metrics!(args["metric_ids"])
          run.update!(tag_names: args["tag_names"]) if args.key?("tag_names")
          text_result(run.reload.as_json)
        else
          error_result(run.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        run = Run.find(args["id"])
        if run.update(args.except("id", "metric_ids", "tag_names").slice("name", "dataset_id", "judge_model", "output_column", "expected_column"))
          run.replace_metrics!(args["metric_ids"]) if args.key?("metric_ids")
          run.update!(tag_names: args["tag_names"]) if args.key?("tag_names")
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
        if run.start!
          text_result(run.reload.as_json)
        else
          text_result(run.failure_summary || run.errors.full_messages.to_sentence)
        end
      end
    end
  end
end

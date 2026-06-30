module CompletionKit
  module McpTools
    module Agreements
      extend Base

      TOOLS = {
        "agreements_list" => {
          description: "List agreements. Filter by run_id, response_id, metric_id, or created_by.",
          inputSchema: {
            type: "object",
            properties: {
              run_id: {type: "integer"},
              response_id: {type: "integer"},
              metric_id: {type: "integer"},
              created_by: {type: "string"}
            },
            required: []
          },
          handler: :list
        },
        "agreements_create" => {
          description: "Upsert an agreement for (run, response, metric, created_by). Verdict is one of agree, disagree, borderline. corrected_score (1..5) is required when verdict is 'disagree'.",
          inputSchema: {
            type: "object",
            properties: {
              run_id: {type: "integer"},
              response_id: {type: "integer"},
              metric_id: {type: "integer"},
              verdict: {type: "string", enum: %w[agree disagree borderline]},
              corrected_score: {type: "number"},
              note: {type: "string"},
              created_by: {type: "string"}
            },
            required: ["run_id", "response_id", "metric_id", "verdict"]
          },
          handler: :create
        }
      }.freeze

      def self.list(args)
        scope = CompletionKit::Agreement.all
        scope = scope.where(run_id: args["run_id"]) if args["run_id"]
        scope = scope.where(response_id: args["response_id"]) if args["response_id"]
        scope = scope.where(metric_id: args["metric_id"]) if args["metric_id"]
        scope = scope.where(created_by: args["created_by"]) if args["created_by"]
        text_result(scope.order(:created_at).map(&:as_json))
      end

      def self.create(args)
        run = CompletionKit::Run.find(args["run_id"])
        response = run.responses.find(args["response_id"])
        metric = CompletionKit::Metric.find(args["metric_id"])
        return error_result("Checks have nothing to calibrate; agreements are only for llm_judge metrics.") if metric.check?

        created_by = args["created_by"].presence || "mcp"

        agreement = CompletionKit::Agreement.find_or_initialize_by(
          run_id: run.id, response_id: response.id, metric_id: metric.id, created_by: created_by
        )
        agreement.assign_attributes(
          metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
          verdict: args["verdict"],
          corrected_score: args["corrected_score"],
          note: args["note"]
        )

        if agreement.save
          text_result(agreement.as_json)
        else
          error_result(agreement.errors.full_messages.join(", "))
        end
      end
    end
  end
end

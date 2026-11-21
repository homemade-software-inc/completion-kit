module CompletionKit
  module McpTools
    module Agreements
      extend Base

      TOOLS = {
        "agreements_list" => {
          description: "List human reviews of the LLM judge's scores: each agree, disagree or borderline verdict, with any corrected score and note. Filter by run_id, response_id, metric_id, or created_by. Use it to see where people disagreed with the judge before improving a metric's rubric. It returns each verdict, oldest first, with its run, response, metric and metric version ids, who recorded it and when.",
          annotations: Base::READ_ONLY,
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
          description: "Record whether a person agrees with the LLM judge's score on one response for one metric, so you can measure how far to trust the judge. The response must belong to the given run. Verdict is one of agree, disagree, borderline. corrected_score (1..5) is required when verdict is 'disagree'. This upserts an agreement for (run, response, metric, created_by): a new verdict with the same created_by (default \"mcp\") replaces the earlier one, including its corrected score and note, and leaving either out clears it. The verdict is filed under the metric's current judge version, which is the version judges_compare counts it for, even when an earlier version scored that response. It works only for llm_judge metrics, because checks have nothing to calibrate. It returns the saved verdict.",
          annotations: Base::DESTRUCTIVE,
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

module CompletionKit
  module McpTools
    module Runs
      extend Base

      TEMPERATURE_DESCRIPTION = "Sampling temperature for generation, 0 to 1. Defaults to the column default. " \
                                "Reasoning models ignore it and the run is flagged temperature_ignored.".freeze

      MAX_TOKENS_DESCRIPTION = "Cap on generated tokens per row. Leave unset to use the provider client's default, " \
                               "which is what silently truncates long outputs and makes the judge score malformed " \
                               "JSON. Set it to whatever the prompt uses in production so the eval matches.".freeze

      JUDGE_TEMPERATURE_DESCRIPTION = "Sampling temperature for the judge, 0 to 1. Defaults to 0 so re-judging the " \
                                      "same output gives the same score. Raise it only to measure judge variance " \
                                      "on purpose; any value above 0 makes the run's scores irreproducible.".freeze

      GENERATION_FIELDS = %w[temperature max_tokens judge_temperature].freeze

      TOOLS = {
        "runs_list" => {
          description: "List all runs",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "runs_get" => {
          description: "Get a run by ID, including \"metric_averages\": a per-metric breakdown with each metric's " \
                       "average score (or pass rate for checks), how many rows it graded, and how many scored low. " \
                       "Use this to find the metric dragging a prompt down without listing responses.",
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
              temperature: {type: "number", description: TEMPERATURE_DESCRIPTION},
              max_tokens: {type: "integer", description: MAX_TOKENS_DESCRIPTION},
              judge_temperature: {type: "number", description: JUDGE_TEMPERATURE_DESCRIPTION},
              output_column: {type: "string", description: "Dataset column to grade when prompt_id is omitted; defaults to \"actual_output\"."},
              expected_column: {type: "string", description: "Dataset column holding each row's answer key / ground truth, graded by checks with compare_to \"expected\" and passed to the judge; defaults to \"expected_output\"."},
              metric_ids: {type: "array", items: {type: "integer"}},
              metric_group_id: {type: "integer", description: "Attach the metrics belonging to this metric group (its current metric_ids). Ignored when metric_ids is also given."},
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
              temperature: {type: "number", description: TEMPERATURE_DESCRIPTION},
              max_tokens: {type: "integer", description: MAX_TOKENS_DESCRIPTION},
              judge_temperature: {type: "number", description: JUDGE_TEMPERATURE_DESCRIPTION},
              output_column: {type: "string"},
              expected_column: {type: "string"},
              metric_ids: {type: "array", items: {type: "integer"}},
              metric_group_id: {type: "integer", description: "Replace the run's metrics with those belonging to this metric group. Ignored when metric_ids is also given."},
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
        },
        "runs_regrade" => {
          description: "Re-grade a run's existing responses with its currently attached metrics, without regenerating. Use after attaching or editing metrics on an already-generated run.",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :regrade
        },
        "runs_rerun" => {
          description: "Create and start a fresh copy of a run with the same prompt, dataset, metrics, and settings. Use when the judge changed and you want a clean run instead of mixing versions.",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :rerun
        },
        "runs_retry_failures" => {
          description: "Re-run only the failed responses of a run, optionally limited to specific response ids via \"only\".",
          inputSchema: {type: "object", properties: {id: {type: "integer"}, only: {type: "array", items: {type: "integer"}}}, required: ["id"]},
          handler: :retry_failures
        }
      }.freeze

      def self.list(_args)
        text_result(Run.display_scoped.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(run_payload(Run.find(args["id"])))
      end

      def self.create(args)
        run = Run.new(args.slice("name", "prompt_id", "dataset_id", "judge_model", "output_column", "expected_column", *GENERATION_FIELDS))
        if run.save
          run.replace_metrics!(resolve_metric_ids(args))
          run.update!(tag_names: args["tag_names"]) if args.key?("tag_names")
          text_result(run_payload(run.reload))
        else
          error_result(run.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        run = Run.find(args["id"])
        if run.update(args.except("id", "metric_ids", "metric_group_id", "tag_names").slice("name", "dataset_id", "judge_model", "output_column", "expected_column", *GENERATION_FIELDS))
          run.replace_metrics!(resolve_metric_ids(args)) if args.key?("metric_ids") || args["metric_group_id"].present?
          run.update!(tag_names: args["tag_names"]) if args.key?("tag_names")
          text_result(run_payload(run.reload))
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
          text_result(run_payload(run.reload))
        else
          text_result(run.failure_summary || run.errors.full_messages.to_sentence)
        end
      end

      def self.regrade(args)
        run = Run.find(args["id"])
        if run.regrade!
          text_result(run_payload(run.reload))
        else
          error_result("Nothing to re-grade. The run has no succeeded responses or no metrics attached.")
        end
      end

      def self.rerun(args)
        new_run = Run.find(args["id"]).rerun!
        if new_run.start!
          text_result(run_payload(new_run.reload))
        else
          error_result(new_run.failure_summary || "Could not start the new run.")
        end
      end

      def self.retry_failures(args)
        run = Run.find(args["id"])
        if run.stale_review_summary.any?
          return error_result("Judge has changed since this run executed. Retry would mix versions in the same run; use runs_rerun instead.")
        end

        run.retry_failures!(only: args["only"])
        text_result(run_payload(run.reload))
      end

      def self.resolve_metric_ids(args)
        return args["metric_ids"] if args.key?("metric_ids")
        return MetricGroup.find(args["metric_group_id"]).metric_ids if args["metric_group_id"].present?

        nil
      end

      def self.run_payload(run)
        json = run.as_json
        warnings = []
        if run.metric_ids.empty?
          warnings << "No metrics are attached, so this run judges nothing. Attach metric_ids or a metric_group_id before generating."
        end
        if run.nondeterministic_judge?
          warnings << "Judge temperature is #{run.judge_temperature}. Judging above 0 makes scores irreproducible: the same output can get a different score on a re-judge. Set judge_temperature to 0 unless you are deliberately measuring judge variance."
        end
        return json if warnings.empty?

        json.merge("warning" => warnings.join(" "))
      end
    end
  end
end

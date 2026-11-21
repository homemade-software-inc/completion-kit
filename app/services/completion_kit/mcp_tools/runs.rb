module CompletionKit
  module McpTools
    module Runs
      extend Base

      TEMPERATURE_DESCRIPTION = "Sampling temperature for generation, 0 to 1. Leave it unset, which is the " \
                                "default, and no temperature is sent at all, so the model applies its own. " \
                                "Most current frontier models refuse the parameter outright; set it only when " \
                                "you are targeting a model that honours it, such as anything served locally " \
                                "through Ollama. A refused value is re-sent without one and the run is " \
                                "flagged temperature_ignored.".freeze

      MAX_TOKENS_DESCRIPTION = "Cap on generated tokens per row. Leave unset to use the provider client's default, " \
                               "which is what silently truncates long outputs and makes the judge score malformed " \
                               "JSON. Set it to whatever the prompt uses in production so the eval matches.".freeze

      JUDGE_TEMPERATURE_DESCRIPTION = "Sampling temperature for the judge, 0 to 1. Defaults to 0 so re-judging the " \
                                      "same output gives the same score. Raise it only to measure judge variance " \
                                      "on purpose; any value above 0 makes the run's scores irreproducible.".freeze

      GENERATION_FIELDS = %w[temperature max_tokens judge_temperature].freeze

      TOOLS = {
        "runs_list" => {
          description: "List your test runs, newest first. A run tests one prompt version against a dataset, or grades existing outputs, and scores each response with your metrics. It returns each run's id, name, status (pending, running, completed or failed), prompt and dataset ids, judge model, average score (1 to 5, 5 is best), check pass rate, per-metric averages and progress. Runs older than the account's history window may be left out. Use it to find a run's id or see recent results, then call runs_get for one run.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "runs_get" => {
          description: "Get one test run's results by id: status, progress, average score (1 to 5, 5 is best), check pass rate, the ids of failed responses, any failure reason, and \"metric_averages\", a per-metric breakdown with each metric's average score (or pass rate for checks), how many rows it graded, and how many scored low. Use this to see how a prompt scored and to find the metric dragging a prompt down without listing responses. Poll it after runs_generate, runs_regrade or runs_rerun until status is completed or failed. The result includes a warning when no metrics are attached or when the judge's scores are not reproducible.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "runs_create" => {
          description: "Set up a test run that scores a prompt's responses on a dataset. Give prompt_id and dataset_id to test a prompt: each dataset row fills the prompt's variables, the prompt's model answers it, and that answer gets scored. Omit prompt_id and provide output_column to score existing outputs by grading a pre-existing dataset column instead of generating new ones. Attach metrics with metric_ids or metric_group_id, and set judge_model, or LLM-judged metrics are skipped; with no metrics the run scores nothing. It fails if the dataset is missing a column the run needs, such as one the prompt uses, or if no configured provider serves judge_model. This only creates the run; call runs_generate to start it. It returns the new run, with a warning if no metrics are attached or if judge_temperature is above 0, which makes scores irreproducible.",
          annotations: Base::ADDITIVE,
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
          description: "Change a test run's settings: name, dataset, judge model, temperature, judge temperature, max tokens, output and expected columns, metrics or tags. The prompt cannot be changed. Passing metric_ids or metric_group_id replaces the run's whole metric list, and tag_names replaces all of its tags. It does not regenerate or rescore anything, and existing responses and scores stay as they are; call runs_regrade to rescore with the new metrics, or runs_rerun for a fresh run. It returns the updated run with the same warnings as runs_get.",
          annotations: Base::DESTRUCTIVE,
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
          description: "Permanently delete a test run and everything in it: its generated responses, their scores and judge feedback, the human agreement verdicts recorded on it (which also drops them from the judge's agreement stats), and any prompt suggestions made from it. This cannot be undone. The prompt, dataset and metrics are kept. Confirm with the user before calling. It returns a short confirmation message.",
          annotations: Base::DESTRUCTIVE,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        },
        "runs_generate" => {
          description: "Start a test run so it produces and scores responses. It is required for every run, including score-only runs (no prompt): it generates responses with the prompt when there is one, and otherwise copies the graded dataset column and grades it. In a prompt run each dataset row goes to the prompt's model, and in either kind of run each LLM-judged metric then scores the result with the run's judge model. LLM-judged metrics are skipped when the run has no judge model. These model calls go to the providers you configured, which may charge for them; checks run without a provider call. The work runs in the background, so poll runs_get until status is completed or failed, and do not call this tool again to check progress. Only a pending or failed run can start, and any refused start marks the run as failed. Calling it on a running or completed run therefore does not start it but marks that run as failed, and a second call would then delete its results. Restarting a failed run first deletes its earlier responses, their scores and any human verdicts on them. For a completed run use runs_rerun, runs_retry_failures or runs_regrade instead. It returns the run with its progress, or the reason it could not start, such as a missing provider key or an empty dataset.",
          annotations: Base::OPEN_WORLD_DESTRUCTIVE,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :generate
        },
        "runs_regrade" => {
          description: "Re-score a test run's existing responses with its currently attached metrics, without regenerating. Use it after attaching or editing metrics on an already-generated run. It first clears every existing score and judge comment on the run's succeeded responses, including scores for metrics no longer attached, so the earlier scores are lost. If the run has checks but no judge model, its LLM-judged scores are cleared and not replaced. Human verdicts already recorded on the run are kept even though people gave them on the earlier scores, and agreement stats then pair them with the new scores. LLM-judged metrics call your judge model's provider; checks do not. The work runs in the background, so poll runs_get for progress. It returns the run, or an error when no configured provider serves the judge model, or when there is nothing to re-grade because the run has no succeeded responses, no metrics, or only LLM-judged metrics and no working judge model.",
          annotations: Base::OPEN_WORLD_DESTRUCTIVE,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :regrade
        },
        "runs_rerun" => {
          description: "Copy a test run and start the copy, with the same prompt version, dataset, metrics, judge model, settings and tags, under a new automatic name. Use it when the judge changed and you want a clean run instead of mixing versions, or to repeat a test. The original run and its scores stay untouched. The copy runs in the background and calls your model providers the same way runs_generate does. To test a different prompt version, create a new run with runs_create instead. It returns the new run; poll runs_get with its id for progress. If the prompt's model or the judge model has no configured provider, or the dataset no longer has a column the run needs, it returns an error and creates nothing. If the copy is created but cannot start, for example because the dataset is empty, it returns the reason and the copy stays as a failed run.",
          annotations: Base::OPEN_WORLD_ADDITIVE,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :rerun
        },
        "runs_retry_failures" => {
          description: "Retry only the parts of a test run that failed, such as provider timeouts, rate limits or judge errors. Failed responses are generated again and failed scores are retried, while responses and scores that succeeded are left alone; optionally limit it to specific response ids via \"only\". It is refused when the judge has changed since the run executed, meaning a metric on the run now has a newer version than the one that scored it, because a retry would mix versions in the same run; use runs_rerun instead. The retries run in the background and call your model providers, except for checks. It returns the run with its progress, or the run unchanged when nothing failed.",
          annotations: Base::OPEN_WORLD_ADDITIVE,
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
        run = Run.new(args.slice("name", "prompt_id", "dataset_id", "judge_model", "output_column", "expected_column", *GENERATION_FIELDS).merge("selected_metric_ids" => resolve_metric_ids(args)))
        if run.save
          run.update!(tag_names: args["tag_names"]) if args.key?("tag_names")
          text_result(run_payload(run.reload))
        else
          error_result(run.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        run = Run.find(args["id"])
        if run.update(args.slice("name", "dataset_id", "judge_model", "output_column", "expected_column", *GENERATION_FIELDS).merge("selected_metric_ids" => resolve_metric_ids(args)))
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
          error_result(run.failure_summary || run.errors.full_messages.to_sentence)
        end
      end

      def self.regrade(args)
        run = Run.find(args["id"])
        if run.regrade!
          text_result(run_payload(run.reload))
        else
          error_result(run.errors.full_messages.to_sentence.presence || "Nothing to re-grade. The run has no succeeded responses or no metrics attached.")
        end
      end

      def self.rerun(args)
        new_run = Run.find(args["id"]).rerun!
        if new_run.start!
          text_result(run_payload(new_run.reload))
        else
          error_result(new_run.failure_summary || "Could not start the new run.")
        end
      rescue ActiveRecord::RecordInvalid => e
        error_result(e.record.errors.full_messages.join(", "))
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
        if run.judge_temperature_ignored?
          warnings << "The judge model refused the temperature parameter, so it was re-sent without one and the provider applied its own default. judge_temperature reads #{run.judge_temperature} but was never applied, and these scores are not reproducible. Pick a judge model that accepts temperature if you need reproducible scoring."
        elsif run.nondeterministic_judge?
          warnings << "Judge temperature is #{run.judge_temperature}. Judging above 0 makes scores irreproducible: the same output can get a different score on a re-judge. Set judge_temperature to 0 unless you are deliberately measuring judge variance."
        end
        return json if warnings.empty?

        json.merge("warning" => warnings.join(" "))
      end
    end
  end
end

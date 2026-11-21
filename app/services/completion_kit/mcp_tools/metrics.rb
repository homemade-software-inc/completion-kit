module CompletionKit
  module McpTools
    module Metrics
      extend Base

      CASE_SENSITIVE_NOTE = "A check with no case_sensitive matches case-insensitively, regex and list_overlap included; " \
        "send case_sensitive: true to match case exactly. Before 0.29.0 a regex check read a missing case_sensitive as case-sensitive."

      CHECK_CONFIG_SCHEMA = {
        type: "object",
        properties: {
          check_kind: {type: "string", enum: CompletionKit::Checks::Registry.kinds},
          target: {type: "string", enum: CompletionKit::Checks::TargetResolver::TARGETS},
          target_path: {type: "string"},
          value: {type: %w[string number array], items: {type: %w[string number]}, description: "Only list_overlap takes a list, as a JSON array or as comma-separated text; every other rule refuses one"},
          pattern: {type: "string"},
          json_path: {type: "string"},
          expected: {},
          compare_to: {type: "string", enum: %w[constant expected]},
          expected_path: {type: "string"},
          min: {type: "number"},
          max: {type: "number"},
          score_by: {type: "string", enum: CompletionKit::Checks::ListOverlap::MEASURES},
          tolerance: {type: %w[number string], description: "A plain number for a fixed amount, or a percentage string such as \"2%\" for a share of the expected value"},
          case_sensitive: {type: "boolean", description: CASE_SENSITIVE_NOTE},
          multiline: {type: "boolean"},
          trim: {type: "boolean"}
        }
      }.freeze

      CHECK_CONFIG_HINT = "For a deterministic check set metric_type:\"check\" and check_config. Per-kind required keys: " \
        "value (contains/not_contains/equals/list_overlap/numeric_equals), pattern (regex), json_path+expected (json_path_equals), " \
        "min and/or max (length_bounds/numeric_bounds); valid_json takes no extra keys. target_path is required when target is json_path; " \
        "a target_path sent with no target sets target to json_path, and one sent with any other target is refused. " \
        "target_path walks array indices, as in items.0.name; any path may start at the root with $., as in $.items.0.name. " \
        "list_overlap grades a list-valued field and stores a fraction rather than a verdict: score_by is recall, precision, f1 or jaccard (recall by default), " \
        "and min is the fraction that counts as a pass (1, a perfect score, by default). " \
        "numeric_bounds and numeric_equals read a number, ignoring the thousands commas and currency symbol a figure is written with; " \
        "a comma counts only as a thousands separator, with three digits after it and no decimal point before it, so 1,5 is not a number; " \
        "numeric_equals takes a tolerance, either a plain number for a fixed amount or a percentage string such as 2% for a share of the expected value. " \
        "#{CASE_SENSITIVE_NOTE} " \
        "Set compare_to:\"expected\" on #{CompletionKit::Checks::Registry.comparable_kinds.join(", ")} to grade against each row's own expected_output (ground truth) " \
        "instead of a constant; drop value (or expected, for json_path_equals) and add expected_path to dig into the answer key when it is JSON."

      TOOLS = {
        "metrics_list" => {
          description: "List every metric in your workspace, newest first. A metric is how CompletionKit scores AI responses. It is either an LLM judge, which grades each response from 1 to 5 (5 is best) against an instruction and rubric, or a check, which scores a response by an exact rule such as contains, equals, regex, valid JSON, a JSON path value, length or number bounds, or list overlap. Returns each metric's id, name, key, type, tags and timestamps, plus its instruction and rubric bands (judges) or its check_config (checks). The full list comes back with no paging. Use it to find a metric id before you score a run, edit a judge or build a metric group.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "metrics_get" => {
          description: "Get one metric by id. Returns its id, name, key, type, tags and timestamps, plus its live judge instruction and 1 to 5 rubric bands (for an LLM judge) or its check_config (for a check). Use it to read exactly how a metric scores AI responses before you change it or explain a score. To see its saved versions and drafts, use metric_versions_list.",
          annotations: Base::READ_ONLY,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "metrics_create" => {
          description: "Create a metric that scores AI responses. By default it is an LLM judge. Send name and instruction (what a good response looks like), and optionally rubric_bands describing 1 to 5 stars, where 5 is best. Any band you leave out gets a default description. For an exact rule instead of a judge, see the check details at the end. The metric's name must be unique in the workspace, ignoring case, spaces and most punctuation, and a renamed metric keeps its original name reserved. A clash fails with the error \"Key has already been taken\". tag_names adds tags and creates any that don't exist yet. Saving a metric scores nothing by itself. Attach it to a run with runs_create or runs_update, then score responses with runs_generate or runs_regrade. Returns the saved metric. #{CHECK_CONFIG_HINT}",
          annotations: Base::ADDITIVE,
          inputSchema: {
            type: "object",
            properties: {
              name: {type: "string"}, instruction: {type: "string"},
              metric_type: {type: "string", enum: CompletionKit::Metric::METRIC_TYPES},
              rubric_bands: {type: "array", items: {type: "object", properties: {stars: {type: "integer"}, description: {type: "string"}}}},
              check_config: CHECK_CONFIG_SCHEMA,
              tag_names: {type: "array", items: {type: "string"}}
            },
            required: ["name"]
          },
          handler: :create
        },
        "metrics_update" => {
          description: "Change a metric's name, judge instruction, rubric bands, check_config, type or tags. This overwrites the metric in place, and the new definition scores every response graded after it. It saves no draft or new version. If the metric already has a live version, scores and verdicts given after the change are still filed under that version, so judges_compare can't tell the old and new definitions apart. Responses already scored keep their old scores until you rescore the run with runs_regrade. Nothing tests the change before it goes live. Fields you leave out stay as they are, but a field you send replaces that whole field: rubric_bands resets any band you leave out to its default description, not its old one, and check_config replaces the whole config. tag_names replaces the whole tag set. A rename keeps the metric's original key, so its old name stays reserved. metric_type cannot change once the metric is in a run, has scores or has versions. Returns the updated metric. #{CHECK_CONFIG_HINT}",
          annotations: Base::DESTRUCTIVE,
          inputSchema: {
            type: "object",
            properties: {
              id: {type: "integer"}, name: {type: "string"}, instruction: {type: "string"},
              metric_type: {type: "string", enum: CompletionKit::Metric::METRIC_TYPES},
              rubric_bands: {type: "array", items: {type: "object", properties: {stars: {type: "integer"}, description: {type: "string"}}}},
              check_config: CHECK_CONFIG_SCHEMA,
              tag_names: {type: "array", items: {type: "string"}}
            },
            required: ["id"]
          },
          handler: :update
        },
        "metrics_delete" => {
          description: "Permanently delete a metric. This also deletes all of its versions and drafts and every human agree, disagree or borderline verdict recorded against them. It removes the metric from every run and metric group and unlinks its tags, though the tags themselves stay. Scores it already gave stay on their responses but are no longer linked to the metric. This cannot be undone. Returns a confirmation message.",
          annotations: Base::DESTRUCTIVE,
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        },
        "metrics_suggest_variants" => {
          description: "Get AI suggestions to improve an LLM judge that disagrees with people. It sends the judge's current instruction and rubric, plus up to 8 recent responses where a person disagreed with the judge's score and up to 6 that a person marked borderline (each input and output cut to 200 characters), to your own model provider. The model is asked for rewrites of the instruction, the rubric or both that close the gap. Each rewrite is saved as a draft metric version with source \"suggestion\", and earlier suggestion drafts are kept. The live judge does not change until you publish a draft with metric_versions_publish. Nothing tests a draft before you publish it. Once it is live and people have recorded verdicts on it with agreements_create, judges_compare shows whether it agrees with people more often than the version it replaced. Returns the saved drafts. It works best after you have recorded disagreements with agreements_create. Checks are refused, because they are exact and have nothing to suggest. count defaults to 1 and is capped at 3. model picks the model that writes the rewrites and defaults to your judge model. The call uses your provider key and runs while you wait. It fails with an error if no judging model is set up or the model you name is unknown. If the model's reply can't be read, nothing is saved and you get a \"no parseable variants\" error. A call your provider refuses, such as one with a bad key, usually ends in that same error.",
          annotations: Base::ADDITIVE,
          inputSchema: {
            type: "object",
            properties: {
              metric_id: {type: "integer"},
              count: {type: "integer", description: "How many variants to request (default 1, max 3). One focused rewrite beats five reworded copies."},
              model: {type: "string", description: "Override the model used to generate variants. Defaults to the configured judge model or an available judging model."}
            },
            required: ["metric_id"]
          },
          handler: :suggest_variants
        }
      }.freeze

      def self.list(_args)
        text_result(Metric.order(created_at: :desc).map(&:as_json))
      end

      def self.get(args)
        text_result(Metric.find(args["id"]).as_json)
      end

      def self.create(args)
        metric = Metric.new(args.slice("name", "instruction", "rubric_bands", "metric_type", "check_config"))
        metric.tag_names = args["tag_names"] if args.key?("tag_names")
        if metric.save
          text_result(metric.reload.as_json)
        else
          error_result(metric.errors.full_messages.join(", "))
        end
      end

      def self.update(args)
        metric = Metric.find(args["id"])
        if metric.update(args.except("id").slice("name", "instruction", "rubric_bands", "metric_type", "check_config"))
          metric.update!(tag_names: args["tag_names"]) if args.key?("tag_names")
          text_result(metric.reload.as_json)
        else
          error_result(metric.errors.full_messages.join(", "))
        end
      end

      def self.delete(args)
        Metric.find(args["id"]).destroy!
        text_result("Metric #{args["id"]} deleted")
      end

      def self.suggest_variants(args)
        metric = Metric.find(args["metric_id"])
        return error_result("Metric ##{metric.id} is a check; checks are exact and have no variants to suggest.") if metric.check?

        generator = MetricVariantGenerator.new(metric, count: args["count"].to_i, model: args["model"])
        variants = generator.call
        return error_result("Variant generator returned no parseable variants. Try again or change the model.") if variants.empty?
        versions = generator.persist!(variants)
        text_result(versions.map(&:as_json))
      end
    end
  end
end

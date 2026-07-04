module CompletionKit
  module McpTools
    module Metrics
      extend Base

      CHECK_CONFIG_SCHEMA = {
        type: "object",
        properties: {
          check_kind: {type: "string", enum: CompletionKit::Checks::Registry.kinds},
          target: {type: "string", enum: CompletionKit::Checks::TargetResolver::TARGETS},
          target_path: {type: "string"},
          value: {type: "string"},
          pattern: {type: "string"},
          json_path: {type: "string"},
          expected: {},
          compare_to: {type: "string", enum: %w[constant expected]},
          expected_path: {type: "string"},
          min: {type: "integer"},
          max: {type: "integer"},
          case_sensitive: {type: "boolean"},
          multiline: {type: "boolean"},
          trim: {type: "boolean"}
        }
      }.freeze

      CHECK_CONFIG_HINT = "For a deterministic check set metric_type:\"check\" and check_config. Per-kind required keys: " \
        "value (contains/not_contains/equals), pattern (regex), json_path+expected (json_path_equals), " \
        "min and/or max (length_bounds); valid_json takes no extra keys. target_path is required when target is json_path. " \
        "For contains, not_contains, and equals, set compare_to:\"expected\" to grade against each row's own expected_output (ground truth) instead of a constant value (drop value); add expected_path to dig into the expected value when it is JSON."

      TOOLS = {
        "metrics_list" => {
          description: "List all metrics",
          inputSchema: {type: "object", properties: {}, required: []},
          handler: :list
        },
        "metrics_get" => {
          description: "Get a metric by ID",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :get
        },
        "metrics_create" => {
          description: "Create a metric with evaluation criteria. #{CHECK_CONFIG_HINT}",
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
          description: "Update a metric. #{CHECK_CONFIG_HINT}",
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
          description: "Delete a metric",
          inputSchema: {type: "object", properties: {id: {type: "integer"}}, required: ["id"]},
          handler: :delete
        },
        "metrics_suggest_variants" => {
          description: "Ask the model to rewrite the metric's judge instruction in N variants targeted at the recent disagreements. Each variant is saved as a draft MetricVersion with source=\"suggestion\". Returns the persisted drafts. Stripe-metering hooks fire via ActiveSupport::Notifications under completion_kit.judge_suggestion.generated.",
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

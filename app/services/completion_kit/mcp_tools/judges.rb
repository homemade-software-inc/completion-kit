module CompletionKit
  module McpTools
    module Judges
      extend Base

      TOOLS = {
        "judges_suggest" => {
          description: "Ask the model to rewrite the metric's judge instruction in N variants targeted at the recent disagreements. Each variant is saved as a draft MetricVersion with source=\"suggestion\". Returns the persisted drafts. Stripe-metering hooks fire via ActiveSupport::Notifications under completion_kit.judge_suggestion.generated.",
          inputSchema: {
            type: "object",
            properties: {
              metric_id: { type: "integer" },
              count: { type: "integer", description: "How many variants to request (default 1, max 3). One focused rewrite beats five reworded copies." },
              model: { type: "string", description: "Override the model used to generate variants. Defaults to CompletionKit.config.judge_model." }
            },
            required: ["metric_id"]
          },
          handler: :suggest
        },
        "judges_replay" => {
          description: "Run the current judge against a dataset (judge-only run). Wraps runs_create with prompt_id omitted and output_column supplied. Re-judges existing dataset outputs so you can compare against human verdicts.",
          inputSchema: {
            type: "object",
            properties: {
              name: { type: "string" },
              metric_id: { type: "integer" },
              dataset_id: { type: "integer" },
              judge_model: { type: "string" },
              output_column: { type: "string", description: "Dataset column with the existing outputs to grade. Defaults to actual_output." }
            },
            required: ["name", "metric_id", "dataset_id", "judge_model"]
          },
          handler: :replay
        },
        "judges_compare" => {
          description: "Compare two metric versions' calibration stats side by side. Pass either two metric_version_ids or one metric_id with metric_version_a_id / metric_version_b_id.",
          inputSchema: {
            type: "object",
            properties: {
              metric_id: { type: "integer" },
              metric_version_a_id: { type: "integer" },
              metric_version_b_id: { type: "integer" }
            },
            required: ["metric_id", "metric_version_a_id", "metric_version_b_id"]
          },
          handler: :compare
        }
      }.freeze

      def self.suggest(args)
        metric = CompletionKit::Metric.find(args["metric_id"])
        generator = CompletionKit::MetricVariantGenerator.new(metric, count: args["count"].to_i, model: args["model"])
        variants = generator.call
        return error_result("Variant generator returned no parseable variants. Try again or change the model.") if variants.empty?
        versions = generator.persist!(variants)
        text_result(versions.map(&:as_json))
      end

      def self.replay(args)
        metric = CompletionKit::Metric.find(args["metric_id"])
        dataset = CompletionKit::Dataset.find(args["dataset_id"])
        run = CompletionKit::Run.new(
          name: args["name"],
          dataset: dataset,
          judge_model: args["judge_model"],
          output_column: args["output_column"].presence || "actual_output"
        )
        if run.save
          run.replace_metrics!([metric.id])
          text_result(run.reload.as_json)
        else
          error_result(run.errors.full_messages.join(", "))
        end
      end

      def self.compare(args)
        metric = CompletionKit::Metric.find(args["metric_id"])
        a = CompletionKit::MetricVersion.where(metric_id: metric.id).find(args["metric_version_a_id"])
        b = CompletionKit::MetricVersion.where(metric_id: metric.id).find(args["metric_version_b_id"])
        stats_a = CompletionKit::MetricCalibrationStats.for(metric, metric_version: a)
        stats_b = CompletionKit::MetricCalibrationStats.for(metric, metric_version: b)
        text_result({
          metric_id: metric.id,
          a: metric_version_payload(a, stats_a),
          b: metric_version_payload(b, stats_b),
          delta: delta_payload(stats_a, stats_b),
          recommendation: recommendation_for(stats_a, stats_b)
        })
      end

      def self.metric_version_payload(version, stats)
        {
          id: version.id, state: version.state, current: version.current,
          source: version.source, created_at: version.created_at,
          sample_size: stats.sample_size,
          agreement_point: stats.agreement_point,
          agreement_low: stats.agreement_low,
          agreement_high: stats.agreement_high,
          borderline_rate: stats.borderline_rate,
          mae: stats.mae, kappa: stats.kappa
        }
      end

      def self.delta_payload(a, b)
        {
          agreement: pair_delta(a.agreement_point, b.agreement_point),
          mae: pair_delta(a.mae, b.mae),
          kappa: pair_delta(a.kappa, b.kappa),
          sample_size: { a: a.sample_size, b: b.sample_size }
        }
      end

      def self.pair_delta(a, b)
        { a: a, b: b, delta: (a.nil? || b.nil?) ? nil : (b - a) }
      end

      def self.recommendation_for(a, b)
        total = a.sample_size + b.sample_size
        if total < 30
          { state: "need_more_data", reason: "Combined n=#{total}; need 30+ to make a call." }
        elsif a.agreement_point.nil? || b.agreement_point.nil?
          { state: "no_change", reason: "Not enough verdicts on one of the versions to compare." }
        else
          lift = b.agreement_point - a.agreement_point
          if lift > 0.03
            { state: "recommend", reason: "B agreement +#{(lift * 100).round}pt over A." }
          elsif lift < -0.03
            { state: "hold", reason: "B agreement #{(lift * 100).round}pt vs A." }
          else
            { state: "no_change", reason: "Agreement within noise (#{(lift * 100).round}pt)." }
          end
        end
      end
    end
  end
end

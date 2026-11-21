module CompletionKit
  module McpTools
    module MetricVersions
      extend Base

      TOOLS = {
        "metric_versions_list" => {
          description: "List every version of one metric's judge or check, drafts and published, newest first. Use it to see how a judge changed over time, find drafts suggested by metrics_suggest_variants or saved from edits in the web app, or pick an older version to restore with metric_versions_publish. Each row carries id, version_number, state (draft or published), source, the current flag marking the live version, and timestamps, plus that version's instruction and rubric bands (judges) or check_config (checks). source is edit or suggestion for versions made those ways, and null for a version saved automatically the first time the metric scored a response or got a verdict. The current version can differ from the metric's live definition if metrics_update changed the metric after that version was saved.",
          annotations: Base::READ_ONLY,
          inputSchema: {
            type: "object",
            properties: {
              metric_id: { type: "integer" }
            },
            required: ["metric_id"]
          },
          handler: :list
        },
        "metric_versions_publish" => {
          description: "Make a metric version the live judge or check that scores new AI responses. It works both to publish a draft and to switch back to an older published version. In one step it marks this version current, marks every other version of the metric not current, and writes this version's instruction and rubric bands (or check_config, for a check) onto the metric, replacing what the metric had. Responses already scored keep their scores. Rescore a run with runs_regrade if you want new ones. Human verdicts stay with the version they were given on. Other published versions stay saved, so you can switch back by publishing one, but a live definition that was never saved as a version is lost. A check version with an invalid check_config is refused. Returns the published version.",
          annotations: Base::DESTRUCTIVE,
          inputSchema: {
            type: "object",
            properties: {
              metric_version_id: { type: "integer" }
            },
            required: ["metric_version_id"]
          },
          handler: :publish
        },
        "metric_versions_dismiss" => {
          description: "Permanently delete a draft version of a metric, whether it came from an edit in the web app or from metrics_suggest_variants. Use it to throw away a suggested judge rewrite you don't want. Published versions are refused. To stop using a published version, publish a different one as current instead. This cannot be undone. Returns the deleted version's id with destroyed: true.",
          annotations: Base::DESTRUCTIVE,
          inputSchema: {
            type: "object",
            properties: {
              metric_version_id: { type: "integer" }
            },
            required: ["metric_version_id"]
          },
          handler: :dismiss
        }
      }.freeze

      def self.list(args)
        metric = CompletionKit::Metric.find(args["metric_id"])
        versions = CompletionKit::MetricVersion.where(metric_id: metric.id).order(version_number: :desc)
        text_result(versions.map(&:as_json))
      end

      def self.publish(args)
        version = CompletionKit::MetricVersion.find(args["metric_version_id"])
        version.publish!
        text_result(version.reload.as_json)
      end

      def self.dismiss(args)
        version = CompletionKit::MetricVersion.find(args["metric_version_id"])
        return error_result("Cannot dismiss a published version. Publish a different version as current instead.") if version.published?
        version.destroy!
        text_result({id: version.id, destroyed: true})
      end
    end
  end
end

module CompletionKit
  module McpTools
    module MetricVersions
      extend Base

      TOOLS = {
        "metric_versions_list" => {
          description: "List every MetricVersion (drafts + published) for a metric, newest first. Each row carries version_number, state, source, current flag, and timestamps.",
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
          description: "Publish a MetricVersion as the live version of its metric. Works for both 'draft → published' and 'revert to an older published version → current'. Transactionally flips current, demotes peers, and writes the version's instruction + rubric_bands back onto the metric so the judge grades against it.",
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
          description: "Destroy a draft MetricVersion (use for either source: 'edit' or source: 'suggestion'). Published versions are refused — to demote a published version, publish a different one as current instead.",
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

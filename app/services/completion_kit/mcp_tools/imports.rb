module CompletionKit
  module McpTools
    module Imports
      extend Base

      TOOLS = {
        "promptfoo_import" => {
          description: "Import a promptfooconfig.yaml. Creates a prompt, a dataset from the test vars, and metrics from the assert blocks (llm-rubric/g-eval become judge metrics; contains/equals/regex/is-json become deterministic check metrics). Returns a summary of what mapped and what was skipped and why; nothing is dropped silently.",
          inputSchema: {
            type: "object",
            properties: {
              config: {type: "string", description: "The full promptfooconfig.yaml contents."}
            },
            required: ["config"]
          },
          handler: :promptfoo_import
        }
      }.freeze

      def self.promptfoo_import(args)
        result = PromptfooImporter.call(args["config"])
        return error_result(result.error) unless result.ok

        text_result(
          prompts: result.prompts,
          dataset: result.dataset,
          metrics: result.metrics,
          providers: result.providers
        )
      end
    end
  end
end

module CompletionKit
  module McpTools
    module Imports
      extend Base

      TOOLS = {
        "promptfoo_import" => {
          description: "Import a promptfoo config (the full promptfooconfig.yaml text) so you can test its prompts and score their responses in CompletionKit. It creates a new prompt for each inline prompt template, one dataset from the tests' vars, and metrics from the assert blocks in tests and defaultTest, with identical asserts imported once. llm-rubric, g-eval, model-graded-closedqa and factuality become LLM judge metrics. contains, icontains, not-contains, not-icontains, equals, regex and is-json become deterministic check metrics. Prompts use the model named by the first provider, or gpt-4o if none is given, and are created even if no saved provider key serves that model. Prompts given as file:// references are skipped, so paste the file's contents instead. It only adds new records, never changes existing ones and does not start a run. Providers are only matched by name against your saved provider keys and reported as matched or unmatched. Any apiKey in the config is ignored, so remove keys before pasting. Returns a summary of what was created and of the prompts and assert types it skipped, with the reason for each. Assert options such as threshold, weight and provider, defaultTest vars, and asserts with no type are dropped without being listed in the summary. If a prompt or the dataset cannot be saved, the whole import is rolled back and nothing is created.",
          annotations: Base::ADDITIVE,
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

module CompletionKit
  module Onboarding
    module Concepts
      DEFINITIONS = {
        credential: {
          name: "Provider Credential",
          definition: "An API key for a model provider such as OpenAI or Anthropic. Encrypted at rest and never returned through the API."
        },
        dataset: {
          name: "Dataset",
          definition: "A CSV of real inputs. Each row becomes one test case."
        },
        prompt: {
          name: "Prompt",
          definition: "A versioned template with {{variable}} placeholders. Editing a prompt that has already been run creates a new version, so past results stay reproducible."
        },
        run: {
          name: "Run",
          definition: "One execution of a prompt against a dataset. Stores every output and the judge's scores."
        },
        response: {
          name: "Response",
          definition: "The model's output for a single dataset row, with the judge's reviews attached."
        },
        metric: {
          name: "Metric",
          definition: "An evaluation dimension. An LLM judge scores each response on a 1-5 rubric, or a deterministic check passes or fails it with no model call."
        }
      }.freeze
    end
  end
end

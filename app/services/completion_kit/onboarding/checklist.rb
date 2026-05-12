module CompletionKit
  module Onboarding
    Step = Data.define(:key, :title, :description, :path_name, :done?)

    class Checklist
      STEP_DEFS = [
        {
          key: :credential,
          title: "Connect a provider",
          description: "Add an API key for OpenAI, Anthropic, or another model provider so you can run prompts and score outputs.",
          path_name: :new_provider_credential_path,
          done: -> { CompletionKit::ProviderCredential.exists? }
        },
        {
          key: :dataset,
          title: "Upload a dataset",
          description: "Drop in a CSV of test inputs. Column headers become the {{variables}} your prompts get evaluated against.",
          path_name: :new_dataset_path,
          done: -> { CompletionKit::Dataset.exists? }
        },
        {
          key: :prompt,
          title: "Write your first prompt",
          description: "Create a versioned prompt template with {{variable}} placeholders. Publishing freezes it; editing makes a new version.",
          path_name: :new_prompt_path,
          done: -> { CompletionKit::Prompt.exists? }
        },
        {
          key: :run,
          title: "Run it",
          description: "Kick off a run against the dataset and watch the responses come in, each scored by the LLM judge against your metrics.",
          path_name: :runs_path,
          done: -> { CompletionKit::Run.exists? }
        }
      ].freeze

      def steps
        @steps ||= STEP_DEFS.map do |d|
          Step.new(
            key: d[:key],
            title: d[:title],
            description: d[:description],
            path_name: d[:path_name],
            done?: d[:done].call
          )
        end
      end

      def complete?
        steps.all?(&:done?)
      end

      # Whether the "Load sample data" button should show — only while neither
      # the dataset nor the prompt step is done (SampleData.install! no-ops
      # otherwise, so the button would do nothing).
      def sample_loadable?
        steps.none? { |s| %i[dataset prompt].include?(s.key) && s.done? }
      end

      def progress
        done = steps.count(&:done?)
        { done: done, total: steps.size, percent: ((done.to_f / steps.size) * 100).round }
      end
    end
  end
end

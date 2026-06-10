require "rails_helper"

module CompletionKit
  module Onboarding
    RSpec.describe SampleData do
      describe ".install!" do
        it "creates one canned dataset and one canned prompt using an available generation model" do
          create(:completion_kit_model, provider: "anthropic", model_id: "claude-gen", supports_generation: true)

          expect { described_class.install! }
            .to change(CompletionKit::Dataset, :count).by(1)
            .and change(CompletionKit::Prompt, :count).by(1)

          dataset = CompletionKit::Dataset.last
          expect(dataset.name).to eq("Sample: Customer tickets")
          expect(dataset.csv_data).to include("ticket").and include("WELCOME20")

          prompt = CompletionKit::Prompt.last
          expect(prompt).to have_attributes(
            name: "Sample: Support reply",
            llm_model: "claude-gen"
          )
          expect(prompt.template).to include("{{ticket}}")
          expect(prompt.family_key).to be_present
          expect(prompt.version_number).to eq(1)
        end

        it "creates only the dataset when no generation model is available" do
          expect { described_class.install! }
            .to change(CompletionKit::Dataset, :count).by(1)
            .and change(CompletionKit::Prompt, :count).by(0)
        end

        it "does not create a provider credential or a run" do
          expect { described_class.install! }
            .to change(CompletionKit::ProviderCredential, :count).by(0)
            .and change(CompletionKit::Run, :count).by(0)
        end

        it "is a no-op when a dataset already exists" do
          create(:completion_kit_dataset)
          expect { described_class.install! }
            .to change(CompletionKit::Dataset, :count).by(0)
            .and change(CompletionKit::Prompt, :count).by(0)
        end

        it "is a no-op when a prompt already exists" do
          create(:completion_kit_prompt)
          expect { described_class.install! }
            .to change(CompletionKit::Dataset, :count).by(0)
            .and change(CompletionKit::Prompt, :count).by(0)
        end
      end
    end
  end
end

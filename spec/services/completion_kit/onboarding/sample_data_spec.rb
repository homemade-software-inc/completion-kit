require "rails_helper"

module CompletionKit
  module Onboarding
    RSpec.describe SampleData do
      describe ".install!" do
        it "creates exactly one canned dataset and one canned prompt" do
          expect { described_class.install! }
            .to change(CompletionKit::Dataset, :count).by(1)
            .and change(CompletionKit::Prompt, :count).by(1)

          dataset = CompletionKit::Dataset.last
          expect(dataset.name).to eq("Sample: Customer tickets")
          expect(dataset.csv_data).to include("ticket").and include("WELCOME20")

          prompt = CompletionKit::Prompt.last
          expect(prompt).to have_attributes(
            name: "Sample: Support reply",
            llm_model: "gpt-4o-mini"
          )
          expect(prompt.template).to include("{{ticket}}")
          expect(prompt.family_key).to be_present
          expect(prompt.version_number).to eq(1)
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

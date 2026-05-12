require "rails_helper"

module CompletionKit
  module Onboarding
    RSpec.describe Checklist do
      subject(:checklist) { described_class.new }

      describe "#steps" do
        it "returns the four setup steps in order, all not done on a fresh install" do
          steps = checklist.steps

          expect(steps.map(&:key)).to eq(%i[credential dataset prompt run])
          expect(steps.map(&:path_name)).to eq(%i[new_provider_credential_path new_dataset_path new_prompt_path runs_path])
          expect(steps).to all(have_attributes(done?: false))
          expect(steps.map(&:title)).to all(be_present)
          expect(steps.map(&:description)).to all(be_present)
        end

        it "memoizes" do
          expect(checklist.steps).to equal(checklist.steps)
        end

        it "marks the credential step done once a provider credential exists" do
          create(:completion_kit_provider_credential)

          credential_step = checklist.steps.find { |s| s.key == :credential }
          expect(credential_step.done?).to be(true)
          expect(checklist.steps.reject(&:done?).map(&:key)).to eq(%i[dataset prompt run])
        end

        it "marks the dataset, prompt, and run steps done when those records exist" do
          dataset = create(:completion_kit_dataset)
          prompt = create(:completion_kit_prompt)
          create(:completion_kit_run, prompt: prompt, dataset: dataset)

          done_keys = checklist.steps.select(&:done?).map(&:key)
          expect(done_keys).to contain_exactly(:dataset, :prompt, :run)
        end
      end

      describe "#complete?" do
        it "is false when any step is outstanding" do
          create(:completion_kit_provider_credential)
          expect(checklist.complete?).to be(false)
        end

        it "is true once all four kinds of record exist" do
          create(:completion_kit_provider_credential)
          dataset = create(:completion_kit_dataset)
          prompt = create(:completion_kit_prompt)
          create(:completion_kit_run, prompt: prompt, dataset: dataset)

          expect(checklist.complete?).to be(true)
        end
      end

      describe "#sample_loadable?" do
        it "is true while neither a dataset nor a prompt exists" do
          expect(checklist.sample_loadable?).to be(true)
          create(:completion_kit_provider_credential)
          expect(described_class.new.sample_loadable?).to be(true)
        end

        it "is false once a dataset exists" do
          create(:completion_kit_dataset)
          expect(checklist.sample_loadable?).to be(false)
        end

        it "is false once a prompt exists" do
          create(:completion_kit_prompt)
          expect(checklist.sample_loadable?).to be(false)
        end
      end

      describe "#progress" do
        it "reports zero progress on a fresh install" do
          expect(checklist.progress).to eq(done: 0, total: 4, percent: 0)
        end

        it "reports a rounded percentage as steps complete" do
          create(:completion_kit_provider_credential)
          expect(checklist.progress).to eq(done: 1, total: 4, percent: 25)
        end

        it "reports full progress once everything is set up" do
          create(:completion_kit_provider_credential)
          dataset = create(:completion_kit_dataset)
          prompt = create(:completion_kit_prompt)
          create(:completion_kit_run, prompt: prompt, dataset: dataset)

          expect(checklist.progress).to eq(done: 4, total: 4, percent: 100)
        end
      end
    end
  end
end

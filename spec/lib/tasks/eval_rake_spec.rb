require "rails_helper"
require "rake"

RSpec.describe "completion_kit rake tasks" do
  before(:all) do
    CompletionKitSpecApp.load_tasks unless Rake::Task.task_defined?("completion_kit:metrics")
  end

  describe "completion_kit:metrics" do
    before { Rake::Task["completion_kit:metrics"].reenable }

    it "lists available metrics" do
      create(:completion_kit_metric, name: "Relevance", key: "relevance")

      expect {
        begin
          Rake::Task["completion_kit:metrics"].invoke
        rescue SystemExit
        end
      }.to output(/relevance/).to_stdout
    end
  end
end

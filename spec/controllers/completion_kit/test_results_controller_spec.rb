require "rails_helper"

RSpec.describe CompletionKit::TestResultsController, type: :controller do
  describe "private helpers" do
    it "returns zero similarity when either side is blank" do
      expect(controller.send(:calculate_similarity, "", "text")).to eq(0)
      expect(controller.send(:calculate_similarity, "text", nil)).to eq(0)
    end

    it "returns zero similarity when tokenization produces no words" do
      expect(controller.send(:calculate_similarity, "!!!", "???")).to eq(0)
    end

    it "reports a simple difference message" do
      expect(controller.send(:highlight_differences, "a", "b")).to eq("Output and expected output differ in content and structure.")
    end
  end
end

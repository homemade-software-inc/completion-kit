require "rails_helper"

RSpec.describe CompletionKit::Suggestion do
  it "is pending while the job drafts and validates, with no template yet" do
    suggestion = build(:completion_kit_suggestion, status: "pending", suggested_template: nil, reasoning: nil)
    expect(suggestion).to be_pending
    expect(suggestion).not_to be_ready
    expect(suggestion).to be_valid
  end

  it "is failed when the model returns nothing usable, with no template" do
    suggestion = build(:completion_kit_suggestion, status: "failed", suggested_template: nil)
    expect(suggestion).to be_failed
    expect(suggestion).not_to be_ready
    expect(suggestion).to be_valid
  end

  it "requires a suggested template once ready" do
    suggestion = build(:completion_kit_suggestion, status: "ready", suggested_template: nil)
    expect(suggestion).not_to be_valid
    expect(suggestion.errors[:suggested_template]).to be_present
  end

  describe "#validated?" do
    def with_summary(summary)
      build(:completion_kit_suggestion, validation_summary: summary)
    end

    it "is false without a validation summary" do
      expect(with_summary(nil)).not_to be_validated
    end

    it "is false when nothing could be re-scored" do
      expect(with_summary("tested" => 0, "after_avg" => nil)).not_to be_validated
    end

    it "is true once an after average is measured" do
      expect(with_summary("before_avg" => 3.0, "after_avg" => 4.0)).to be_validated
    end
  end

  describe "#net_negative?" do
    def with_summary(summary)
      build(:completion_kit_suggestion, validation_summary: summary)
    end

    it "is false without a validation summary" do
      expect(with_summary(nil)).not_to be_net_negative
    end

    it "is false when nothing could be re-scored" do
      expect(with_summary("tested" => 0, "after_avg" => nil)).not_to be_net_negative
    end

    it "is true when the after average drops below the before average" do
      expect(with_summary("before_avg" => 4.0, "after_avg" => 3.0, "improved" => 1, "regressed" => 0)).to be_net_negative
    end

    it "is true when more rows regressed than improved" do
      expect(with_summary("before_avg" => 3.0, "after_avg" => 3.0, "improved" => 1, "regressed" => 2)).to be_net_negative
    end

    it "is false when the suggestion holds or improves" do
      expect(with_summary("before_avg" => 3.0, "after_avg" => 4.0, "improved" => 2, "regressed" => 0)).not_to be_net_negative
    end
  end
end

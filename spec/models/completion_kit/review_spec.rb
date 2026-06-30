require "rails_helper"

RSpec.describe CompletionKit::Review, type: :model do
  describe "#check?" do
    it "is true for a review of a check version" do
      expect(create(:completion_kit_review, :check).check?).to be(true)
    end

    it "is false for a rubric review" do
      expect(create(:completion_kit_review).check?).to be(false)
    end

    it "is false when the review has no metric_version" do
      review = build(:completion_kit_review, metric_version: nil)
      expect(review.check?).to be(false)
    end
  end

  describe "#passed?" do
    it "reflects the passed column across true, false, and nil" do
      expect(build(:completion_kit_review, passed: true).passed?).to be(true)
      expect(build(:completion_kit_review, passed: false).passed?).to be(false)
      expect(build(:completion_kit_review, passed: nil).passed?).to be(false)
    end
  end

  describe "status" do
    let(:response) { create(:completion_kit_response) }

    it "validates inclusion in pending/retrying/succeeded/failed" do
      review = build(:completion_kit_review, response: response, status: "evaluated")
      expect(review).not_to be_valid
    end

    %w[pending retrying].each do |status|
      it "is not terminal? when status is #{status}" do
        expect(build(:completion_kit_review, response: response, status: status)).not_to be_terminal
      end
    end

    %w[succeeded failed].each do |status|
      it "is terminal? when status is #{status}" do
        expect(build(:completion_kit_review, response: response, status: status)).to be_terminal
      end
    end

    it "is succeeded? when status is succeeded" do
      expect(build(:completion_kit_review, response: response, status: "succeeded")).to be_succeeded
    end

    it "is not succeeded? when status is failed" do
      expect(build(:completion_kit_review, response: response, status: "failed")).not_to be_succeeded
    end
  end

  describe "metric version requirement" do
    it "is invalid without a metric version when it has a metric" do
      response = create(:completion_kit_response)
      metric = create(:completion_kit_metric)
      review = build(:completion_kit_review, response: response, metric: metric, metric_version: nil)
      expect(review).not_to be_valid
      expect(review.errors[:metric_version]).to be_present
    end

    it "is valid with a metric version" do
      expect(create(:completion_kit_review)).to be_valid
    end
  end

  describe "#error_payload" do
    let(:response) { create(:completion_kit_response) }

    it "returns nil when error_class is blank" do
      review = build(:completion_kit_review, response: response)
      expect(review.error_payload).to be_nil
    end

    it "returns a structured hash when error fields are populated" do
      review = build(:completion_kit_review, response: response,
        error_provider: "anthropic", error_class: "Faraday::TimeoutError",
        error_status: nil, error_message: "boom")
      expect(review.error_payload).to eq(
        provider: "anthropic", class: "Faraday::TimeoutError", status: nil, message: "boom"
      )
    end
  end
end

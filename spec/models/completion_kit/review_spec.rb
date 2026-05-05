require "rails_helper"

RSpec.describe CompletionKit::Review, type: :model do
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

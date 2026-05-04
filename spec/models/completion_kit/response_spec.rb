require "rails_helper"

RSpec.describe CompletionKit::Response, type: :model do
  it "allows nil input_data for no-dataset runs" do
    response = build(:completion_kit_response, input_data: nil)
    expect(response).to be_valid
  end

  it "requires response_text when status is succeeded" do
    response = build(:completion_kit_response, status: "succeeded", response_text: nil)
    expect(response).not_to be_valid
  end

  describe "#error_payload" do
    it "returns nil when error_class is blank" do
      response = build(:completion_kit_response)
      expect(response.error_payload).to be_nil
    end

    it "returns a hash with error details when error_class is present" do
      response = build(:completion_kit_response, :failed)
      expect(response.error_payload).to eq(
        provider: "openai",
        class: "Faraday::TimeoutError",
        status: nil,
        message: "execution expired"
      )
    end
  end

  describe "status" do
    it "defaults to pending on a new record" do
      response = build(:completion_kit_response, status: nil, response_text: "anything")
      response.valid?
      expect(response.status).to eq("pending")
    end

    it "validates inclusion in the STATUSES list" do
      response = build(:completion_kit_response, status: "weird")
      expect(response).not_to be_valid
      expect(response.errors[:status]).to be_present
    end

    %w[pending retrying].each do |status|
      it "is not terminal? when status is #{status}" do
        expect(build(:completion_kit_response, status: status)).not_to be_terminal
      end
    end

    %w[succeeded failed].each do |status|
      it "is terminal? when status is #{status}" do
        expect(build(:completion_kit_response, status: status)).to be_terminal
      end
    end
  end
end

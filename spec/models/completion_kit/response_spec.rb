require "rails_helper"

RSpec.describe CompletionKit::Response, type: :model do
  describe ".with_body_preview" do
    it "loads only a truncated response_text while keeping the other attributes intact" do
      response = create(:completion_kit_response, status: "succeeded", response_text: "A" * 2000, attempts: 3)

      previewed = CompletionKit::Response.with_body_preview(700).find(response.id)

      expect(previewed.response_text.length).to eq(700)
      expect(previewed.status).to eq("succeeded")
      expect(previewed.attempts).to eq(3)
      expect(previewed.run_id).to eq(response.run_id)
    end

    it "leaves the full body available through an ordinary load (detail/broadcast path)" do
      response = create(:completion_kit_response, status: "succeeded", response_text: "B" * 2000)
      expect(CompletionKit::Response.find(response.id).response_text.length).to eq(2000)
    end
  end

  it "allows nil input_data for no-dataset runs" do
    response = build(:completion_kit_response, input_data: nil)
    expect(response).to be_valid
  end

  it "requires response_text when status is succeeded" do
    response = build(:completion_kit_response, status: "succeeded", response_text: nil)
    expect(response).not_to be_valid
  end

  it "allows a nil response_text on a succeeded response for an input_data-only check run" do
    dataset = create(:completion_kit_dataset, csv_data: "input,topic\nhello,greeting\n")
    check = create(:completion_kit_metric, :check, check_config: { "check_kind" => "valid_json", "target" => "input_data" })
    run = CompletionKit::Run.new(prompt: nil, dataset: dataset, name: "input check")
    run.run_metrics.build(metric: check, position: 1)
    run.save!

    response = build(:completion_kit_response, run: run, status: "succeeded", response_text: nil)
    expect(response).to be_valid
  end

  it "still requires response_text on a succeeded response with no run" do
    response = build(:completion_kit_response, run: nil, status: "succeeded", response_text: nil)
    expect(response).not_to be_valid
    expect(response.errors[:response_text]).to be_present
  end

  it "does not let a broadcast failure propagate out of the save" do
    response = create(:completion_kit_response)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update).and_raise(StandardError, "cable down")
    allow(Rails.logger).to receive(:error)

    expect { response.update!(response_text: "still saved") }.not_to raise_error
    expect(response.reload.response_text).to eq("still saved")
    expect(Rails.logger).to have_received(:error).with(/broadcast failed/)
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

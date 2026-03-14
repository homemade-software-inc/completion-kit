require "rails_helper"

RSpec.describe CompletionKit::Response, type: :model do
  it "allows nil input_data for no-dataset runs" do
    response = build(:completion_kit_response, input_data: nil)
    expect(response).to be_valid
  end

  it "requires response_text" do
    response = build(:completion_kit_response, response_text: nil)
    expect(response).not_to be_valid
  end
end

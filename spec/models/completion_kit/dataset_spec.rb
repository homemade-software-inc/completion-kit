require "rails_helper"

RSpec.describe CompletionKit::Dataset, type: :model do
  describe "#row_count" do
    it "returns the number of data rows for valid CSV" do
      dataset = build(:completion_kit_dataset)
      expect(dataset.row_count).to eq(1)
    end

    it "returns 0 when csv_data is blank" do
      dataset = build(:completion_kit_dataset, csv_data: "")
      expect(dataset.row_count).to eq(0)
    end

    it "returns 0 when csv_data is malformed" do
      dataset = build(:completion_kit_dataset, csv_data: "col1,col2\n\"unclosed quote\n")
      expect(dataset.row_count).to eq(0)
    end
  end
end

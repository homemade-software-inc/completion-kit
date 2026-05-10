require "rails_helper"

RSpec.describe CompletionKit::Dataset, type: :model do
  describe "destroy cascade" do
    it "destroys associated runs (and their responses + reviews)" do
      prompt = create(:completion_kit_prompt, template: "Static prompt without variables")
      dataset = create(:completion_kit_dataset)
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset)
      response = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: response)

      expect { dataset.destroy! }
        .to change(CompletionKit::Run, :count).by(-1)
        .and change(CompletionKit::Response, :count).by(-1)
        .and change(CompletionKit::Review, :count).by(-1)
    end
  end

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

  describe "#headers" do
    it "returns parsed column headers from the first CSV line" do
      dataset = build(:completion_kit_dataset, csv_data: "name,topic,extra\nfoo,bar,baz\n")
      expect(dataset.headers).to eq(%w[name topic extra])
    end

    it "returns an empty array when csv_data is blank" do
      dataset = build(:completion_kit_dataset, csv_data: "")
      expect(dataset.headers).to eq([])
    end

    it "returns an empty array when first line is malformed" do
      dataset = build(:completion_kit_dataset, csv_data: "\"unclosed,quote\nfoo,bar\n")
      expect(dataset.headers).to eq([])
    end
  end
end

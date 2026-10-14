require "rails_helper"

RSpec.describe CompletionKit::Dataset, type: :model do
  describe "csv_data size limit" do
    around do |example|
      original = CompletionKit.config.max_upload_bytes
      CompletionKit.config.max_upload_bytes = 32
      example.run
    ensure
      CompletionKit.config.max_upload_bytes = original
    end

    it "rejects csv_data larger than the configured upload limit" do
      dataset = build(:completion_kit_dataset, csv_data: "col\n" + ("x" * 100))
      expect(dataset).not_to be_valid
      expect(dataset.errors[:csv_data].join).to match(/too large/)
    end

    it "accepts csv_data within the limit" do
      dataset = build(:completion_kit_dataset, csv_data: "a\nb\n")
      expect(dataset).to be_valid
    end
  end

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

    it "reads the header row whichever line ending the file uses" do
      expect(build(:completion_kit_dataset, csv_data: "name, topic\r\nfoo,bar\r\n").headers).to eq(%w[name topic])
      expect(build(:completion_kit_dataset, csv_data: "name,topic\rfoo,bar\r").headers).to eq(%w[name topic])
      expect(build(:completion_kit_dataset, csv_data: "name,topic").headers).to eq(%w[name topic])
      expect(build(:completion_kit_dataset, csv_data: "\nfoo,bar\n").headers).to eq([])
    end

    it "hands the CSV parser only the header row, never the rest of a large file" do
      sizes = track_csv_reads
      dataset = build(:completion_kit_dataset, csv_data: "name,topic\n#{"a,b\n" * 250_000}")

      expect(dataset.headers).to eq(%w[name topic])
      expect(sizes).to eq(["name,topic".bytesize])
    end

    it "reads a header row that fills the limit" do
      header = "a" * described_class::HEADER_ROW_LIMIT
      expect(build(:completion_kit_dataset, csv_data: "#{header}\n1\n").headers).to eq([header])
      expect(build(:completion_kit_dataset, csv_data: header).headers).to eq([header])
    end

    it "returns an empty array without parsing when the header row runs past the limit" do
      sizes = track_csv_reads
      long = "a," * described_class::HEADER_ROW_LIMIT

      expect(build(:completion_kit_dataset, csv_data: long).headers).to eq([])
      expect(build(:completion_kit_dataset, csv_data: "#{long}\n1\n").headers).to eq([])
      expect(sizes).to be_empty
    end
  end

  describe "#any_rows?" do
    it "is true when a data row follows the header row, blank rows included, as CSV counts them" do
      ["name\nfoo\n", "name\nfoo", "name\r\nfoo\r\n", "name\rfoo\r", "name\n\n"].each do |csv|
        expect(build(:completion_kit_dataset, csv_data: csv).any_rows?).to be(true), "for #{csv.inspect}"
      end
    end

    it "is false when the file holds only a header row" do
      ["name\n", "name", "name\r\n", "name\r", "\n", "", nil].each do |csv|
        expect(build(:completion_kit_dataset, csv_data: csv).any_rows?).to be(false), "for #{csv.inspect}"
      end
    end

    it "agrees with row_count on whether a well-formed file has rows" do
      ["a,b\n1,2\n3,4\n", "a,b\n", "a,b\r\n1,2\r\n", "a,b\n\n1,2\n", "a,b"].each do |csv|
        dataset = build(:completion_kit_dataset, csv_data: csv)
        expect(dataset.any_rows?).to eq(dataset.row_count.positive?), "for #{csv.inspect}"
      end
    end

    it "is false when the header row runs past the limit" do
      expect(build(:completion_kit_dataset, csv_data: "a" * (described_class::HEADER_ROW_LIMIT + 1)).any_rows?).to be(false)
    end

    it "never parses the file" do
      sizes = track_csv_reads

      expect(build(:completion_kit_dataset, csv_data: "name\n#{"x\n" * 100_000}").any_rows?).to be(true)
      expect(sizes).to be_empty
    end
  end

  describe "header row limit" do
    it "rejects csv_data whose header row runs past the limit" do
      dataset = build(:completion_kit_dataset, csv_data: "#{"a" * (described_class::HEADER_ROW_LIMIT + 1)}\n1\n")

      expect(dataset).not_to be_valid
      expect(dataset.errors[:csv_data]).to eq(["has a header row longer than 64 KB"])
    end

    it "keeps an existing dataset saveable when its csv_data does not change" do
      dataset = build(:completion_kit_dataset, csv_data: "a" * (described_class::HEADER_ROW_LIMIT + 1))
      dataset.save!(validate: false)

      expect(dataset.update(name: "Renamed")).to be(true)
    end
  end
end

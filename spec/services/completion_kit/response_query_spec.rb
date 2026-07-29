require "rails_helper"

RSpec.describe CompletionKit::ResponseQuery do
  let(:run) { create(:completion_kit_run) }

  def response_with_score(score, **attrs)
    response = create(:completion_kit_response, run: run, **attrs)
    create(:completion_kit_review, response: response, ai_score: score) if score
    response
  end

  def ids(**options)
    described_class.new(run, **options).relation.map(&:id)
  end

  describe "#relation" do
    it "orders by id and keeps every row when nothing is scoped" do
      first = response_with_score(nil)
      second = response_with_score(nil)
      expect(ids).to eq([first.id, second.id])
    end

    it "filters by status" do
      create(:completion_kit_response, run: run, status: "succeeded")
      failed = create(:completion_kit_response, :failed, run: run)
      expect(ids(status: "failed")).to eq([failed.id])
    end

    it "sorts ascending by the row's average score" do
      high = response_with_score(5.0)
      low = response_with_score(1.0)
      middle = response_with_score(3.0)
      expect(ids(sort: "score_asc")).to eq([low.id, middle.id, high.id])
    end

    it "sorts descending by the row's average score" do
      high = response_with_score(5.0)
      low = response_with_score(1.0)
      expect(ids(sort: "score_desc")).to eq([high.id, low.id])
    end

    it "keeps unscored rows last when sorting without a score filter" do
      scored = response_with_score(4.0)
      unscored = response_with_score(nil)
      expect(ids(sort: "score_asc")).to eq([scored.id, unscored.id])
    end

    it "drops unscored rows once a score filter is applied" do
      scored = response_with_score(4.0)
      response_with_score(nil)
      expect(ids(min_score: 1)).to eq([scored.id])
    end

    it "applies min_score" do
      low = response_with_score(2.0)
      high = response_with_score(4.0)
      expect(ids(min_score: 3)).to eq([high.id])
      expect(ids(min_score: 2)).to eq([low.id, high.id])
    end

    it "applies max_score" do
      low = response_with_score(2.0)
      high = response_with_score(4.0)
      expect(ids(max_score: 3)).to eq([low.id])
      expect(ids(max_score: 4)).to eq([low.id, high.id])
    end

    it "keeps id order when filtering without a score sort" do
      first = response_with_score(5.0)
      second = response_with_score(1.0)
      expect(ids(min_score: 1)).to eq([first.id, second.id])
    end

    it "averages a row's reviews the way Response#score does" do
      response = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: response, ai_score: 1.0)
      create(:completion_kit_review, response: response, ai_score: 4.0)
      expect(response.reload.score).to eq(2.5)
      expect(ids(min_score: 2.5)).to eq([response.id])
      expect(ids(max_score: 2.4)).to eq([])
    end

    it "ignores an unknown sort" do
      first = response_with_score(5.0)
      second = response_with_score(1.0)
      expect(ids(sort: "bogus")).to eq([first.id, second.id])
    end
  end

  describe "#serialize" do
    let(:response) { create(:completion_kit_response, run: run, response_text: "Body") }

    before { create(:completion_kit_review, response: response, metric_name: "Tone", ai_score: 3.0) }

    it "returns the full payload when no fields are requested" do
      json = described_class.new(run).serialize(response)
      expect(json).to include(:id, :run_id, :input_data, :response_text, :reviews, :status)
    end

    it "always includes id and honours a comma-separated string" do
      json = described_class.new(run, fields: "score, status").serialize(response)
      expect(json.keys).to match_array(%i[id score status])
    end

    it "trims reviews to the requested keys" do
      json = described_class.new(run, fields: %w[reviews.ai_score]).serialize(response)
      expect(json.keys).to match_array(%i[id reviews])
      expect(json[:reviews]).to eq([{ai_score: BigDecimal("3.0")}])
    end

    it "omits reviews when only top-level fields are requested" do
      json = described_class.new(run, fields: %w[response_text]).serialize(response)
      expect(json.keys).to match_array(%i[id response_text])
    end

    it "ignores blank field names" do
      json = described_class.new(run, fields: ["", "  ", "status"]).serialize(response)
      expect(json.keys).to match_array(%i[id status])
    end
  end
end

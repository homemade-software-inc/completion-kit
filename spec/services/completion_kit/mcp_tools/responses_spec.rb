require "rails_helper"

RSpec.describe CompletionKit::McpTools::Responses do
  describe ".definitions" do
    it "returns 2 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(2)
      expect(defs.map { |d| d[:name] }).to match_array(%w[responses_list responses_get])
    end

    it "advertises the payload-trimming arguments on responses_list" do
      properties = described_class::TOOLS["responses_list"][:inputSchema][:properties]
      expect(properties.keys).to include(:limit, :offset, :status, :min_score, :max_score, :sort, :fields)
    end
  end

  describe ".call" do
    let!(:prompt) { create(:completion_kit_prompt) }
    let!(:run) { create(:completion_kit_run, prompt: prompt) }
    let!(:response_record) { create(:completion_kit_response, run: run, response_text: "Hello") }

    def list(args = {})
      result = described_class.call("responses_list", {"run_id" => run.id}.merge(args))
      JSON.parse(result[:content].first[:text])
    end

    it "lists responses for a run inside a paging envelope" do
      content = list
      expect(content).to include("total" => 1, "limit" => 50, "offset" => 0, "returned" => 1)
      expect(content["responses"].first["response_text"]).to eq("Hello")
    end

    it "pages with limit and offset while reporting the unpaged total" do
      2.times { create(:completion_kit_response, run: run) }
      content = list("limit" => 2, "offset" => 1)
      expect(content).to include("total" => 3, "limit" => 2, "offset" => 1, "returned" => 2)
      expect(content["responses"].length).to eq(2)
    end

    it "clamps a non-positive limit to the default and a negative offset to zero" do
      content = list("limit" => 0, "offset" => -5)
      expect(content).to include("limit" => 50, "offset" => 0)
    end

    it "caps an oversized limit" do
      expect(list("limit" => 10_000)["limit"]).to eq(500)
    end

    it "projects only the requested fields" do
      create(:completion_kit_review, response: response_record, metric_name: "Tone", ai_score: 2.0)
      row = list("fields" => ["score", "reviews.metric_name", "reviews.ai_score"])["responses"].first
      expect(row.keys).to match_array(%w[id score reviews])
      expect(row["reviews"]).to eq([{"metric_name" => "Tone", "ai_score" => "2.0"}])
    end

    it "returns the worst rows first when sorted by score ascending" do
      low = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: response_record, ai_score: 5.0)
      create(:completion_kit_review, response: low, ai_score: 1.0)
      ids = list("sort" => "score_asc", "fields" => ["id"])["responses"].map { |r| r["id"] }
      expect(ids).to eq([low.id, response_record.id])
    end

    it "filters to low scorers with max_score" do
      low = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: response_record, ai_score: 5.0)
      create(:completion_kit_review, response: low, ai_score: 2.0)
      content = list("max_score" => 3, "fields" => ["id"])
      expect(content["total"]).to eq(1)
      expect(content["responses"].map { |r| r["id"] }).to eq([low.id])
    end

    it "filters by status" do
      failed = create(:completion_kit_response, :failed, run: run)
      content = list("status" => "failed", "fields" => ["id"])
      expect(content["responses"].map { |r| r["id"] }).to eq([failed.id])
    end

    it "gets a response by id" do
      result = described_class.call("responses_get", {"run_id" => run.id, "id" => response_record.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(response_record.id)
    end
  end
end

require "rails_helper"

RSpec.describe CompletionKit::McpTools::Judges do
  let(:metric) { create(:completion_kit_metric) }

  def stub_llm(response_text)
    client = instance_double("CompletionKit::OpenAiClient")
    allow(client).to receive(:generate_completion).and_return(response_text)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
  end

  describe "judges_suggest" do
    it "persists variants as drafts and returns their payloads" do
      stub_llm("VARIANT:\nREASONING: r\nINSTRUCTION:\nrewrite me\nEND_VARIANT")
      result = described_class.call("judges_suggest", {"metric_id" => metric.id, "count" => 2})
      payload = JSON.parse(result[:content].first[:text])
      expect(payload.length).to eq(1)
      expect(payload.first["source"]).to eq("suggestion")
      expect(payload.first["state"]).to eq("draft")
      expect(CompletionKit::MetricVersion.drafts.where(metric_id: metric.id).count).to eq(1)
    end

    it "clamps count to a max of 3" do
      blocks = Array.new(7) { |i| "VARIANT:\nREASONING: r#{i}\nINSTRUCTION:\nv#{i}\nEND_VARIANT" }
      stub_llm(blocks.join("\n\n"))
      described_class.call("judges_suggest", {"metric_id" => metric.id, "count" => 99})
      expect(CompletionKit::MetricVersion.drafts.where(metric_id: metric.id).count).to eq(3)
    end

    it "falls back to the default count when none is supplied" do
      blocks = Array.new(7) { |i| "VARIANT:\nREASONING: r#{i}\nINSTRUCTION:\nv#{i}\nEND_VARIANT" }
      stub_llm(blocks.join("\n\n"))
      described_class.call("judges_suggest", {"metric_id" => metric.id})
      expect(CompletionKit::MetricVersion.drafts.where(metric_id: metric.id).count)
        .to eq(CompletionKit::MetricVariantGenerator::DEFAULT_VARIANT_COUNT)
    end

    it "returns isError when the model returns nothing parseable" do
      stub_llm("no variants here")
      result = described_class.call("judges_suggest", {"metric_id" => metric.id})
      expect(result[:isError]).to be(true)
    end
  end
end

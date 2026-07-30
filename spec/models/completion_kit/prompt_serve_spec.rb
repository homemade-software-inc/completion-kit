require "rails_helper"

RSpec.describe CompletionKit::PromptServe, type: :model do
  let(:prompt) { create(:completion_kit_prompt) }

  describe ".record!" do
    it "creates the day's row on the first fetch" do
      expect { described_class.record!(prompt) }.to change(described_class, :count).by(1)

      row = described_class.last
      expect(row.prompt_id).to eq(prompt.id)
      expect(row.family_key).to eq(prompt.family_key)
      expect(row.served_on).to eq(Date.current)
      expect(row.serve_count).to eq(1)
      expect(row.last_served_at).to be_present
    end

    it "increments the existing row rather than adding another" do
      described_class.record!(prompt)

      expect { 3.times { described_class.record!(prompt) } }.not_to change(described_class, :count)
      expect(described_class.last.serve_count).to eq(4)
    end

    it "keeps a separate row per prompt" do
      other = create(:completion_kit_prompt)
      described_class.record!(prompt)
      described_class.record!(other)

      expect(described_class.count).to eq(2)
    end

    it "falls back to incrementing when another request wins the race to insert" do
      allow(described_class).to receive(:create!) do |*|
        # Stand in for the concurrent request that inserted the row first.
        described_class.insert!({ prompt_id: prompt.id, family_key: prompt.family_key,
                                  served_on: Date.current, serve_count: 1,
                                  created_at: Time.current, updated_at: Time.current })
        raise ActiveRecord::RecordNotUnique, "duplicate key"
      end

      expect { described_class.record!(prompt) }.not_to raise_error
      expect(described_class.sole.serve_count).to eq(2)
    end
  end

  describe ".summary_for" do
    it "reports zeroes for a prompt nobody has fetched" do
      summary = described_class.summary_for(prompt)

      expect(summary[:total]).to eq(0)
      expect(summary[7]).to eq(0)
      expect(summary[30]).to eq(0)
      expect(summary[:last_served_at]).to be_nil
    end

    it "totals the whole family and windows by day" do
      newer = prompt.clone_as_new_version
      newer.save!

      described_class.create!(prompt_id: prompt.id, family_key: prompt.family_key,
                              served_on: Date.current, serve_count: 5, last_served_at: Time.current)
      described_class.create!(prompt_id: newer.id, family_key: prompt.family_key,
                              served_on: Date.current - 10, serve_count: 7)
      described_class.create!(prompt_id: nil, family_key: prompt.family_key,
                              served_on: Date.current - 45, serve_count: 100)

      summary = described_class.summary_for(prompt)

      expect(summary[:total]).to eq(112)
      expect(summary[7]).to eq(5)
      expect(summary[30]).to eq(12)
      expect(summary[:last_served_at]).to be_present
    end
  end
end

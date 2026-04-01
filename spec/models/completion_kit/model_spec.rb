require "rails_helper"

RSpec.describe CompletionKit::Model, type: :model do
  it "validates presence of provider, model_id, and status" do
    model = described_class.new
    expect(model).not_to be_valid
    expect(model.errors[:provider]).to be_present
    expect(model.errors[:model_id]).to be_present
    expect(model.errors[:status]).to be_present
  end

  it "validates uniqueness of model_id scoped to provider" do
    described_class.create!(provider: "openai", model_id: "gpt-4o-mini", status: "active")
    duplicate = described_class.new(provider: "openai", model_id: "gpt-4o-mini", status: "active")
    expect(duplicate).not_to be_valid
  end

  it "validates status inclusion" do
    model = described_class.new(provider: "openai", model_id: "gpt-x", status: "bogus")
    expect(model).not_to be_valid
  end

  describe "scopes" do
    before do
      described_class.create!(provider: "openai", model_id: "gpt-gen", status: "active", supports_generation: true, supports_judging: false)
      described_class.create!(provider: "openai", model_id: "gpt-judge", status: "active", supports_generation: true, supports_judging: true)
      described_class.create!(provider: "openai", model_id: "gpt-retired", status: "retired", supports_generation: true, supports_judging: true)
      described_class.create!(provider: "openai", model_id: "gpt-failed", status: "failed", supports_generation: false, supports_judging: false)
    end

    it ".for_generation returns active models that support generation" do
      ids = described_class.for_generation.pluck(:model_id)
      expect(ids).to contain_exactly("gpt-gen", "gpt-judge")
    end

    it ".for_judging returns active models that support judging" do
      ids = described_class.for_judging.pluck(:model_id)
      expect(ids).to contain_exactly("gpt-judge")
    end

    it ".active returns only active models" do
      ids = described_class.active.pluck(:model_id)
      expect(ids).to contain_exactly("gpt-gen", "gpt-judge")
    end
  end
end

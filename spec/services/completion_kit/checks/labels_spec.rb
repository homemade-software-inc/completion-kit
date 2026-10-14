require "rails_helper"

RSpec.describe CompletionKit::Checks::Labels do
  let(:registry) { CompletionKit::Checks::Registry }

  it "names every check kind, target and measure" do
    expect(described_class::KINDS.keys).to eq(registry.kinds)
    expect(described_class::TARGETS.keys).to eq(CompletionKit::Checks::TargetResolver::TARGETS)
    expect(described_class::SCORE_BY.keys).to eq(CompletionKit::Checks::ListOverlap::MEASURES)
    expect(described_class::COMPARE_TO.keys).to eq(%w[constant expected])
  end

  it "labels every key a check config can hold" do
    keys = registry::SHARED_KEYS + registry::CONFIG_KEYS.values.flatten
    expect(keys.uniq - described_class::FIELDS.keys).to be_empty
  end

  it "describes all four ways to score a list, each under its own name" do
    names = described_class::SCORE_BY.values.map { |label| label.split(":").first }
    expect(names).to eq(%w[Coverage Accuracy Balance Overlap])
    expect(described_class.hint("score_by")).to eq(
      "Coverage ignores extra items, and accuracy ignores missing ones. Balance weighs the two equally. " \
      "Overlap divides the shared items by every item in either list, so it never scores higher than the other three."
    )
  end

  it "humanizes a kind, target or field it does not know" do
    expect(described_class.kind("mystery_kind")).to eq("Mystery kind")
    expect(described_class.target("elsewhere")).to eq("Elsewhere")
    expect(described_class.field("some_key")).to eq("Some key")
  end

  it "names a field the way the chosen rule does" do
    expect(described_class.field("min", "list_overlap")).to eq("Lowest score that passes")
    expect(described_class.field("min", "numeric_bounds")).to eq("Lowest allowed")
    expect(described_class.field("min")).to eq("Minimum")
    expect(described_class.field("value", "numeric_equals")).to eq("Expected number")
    expect(described_class.field("value", "contains")).to eq("Text to look for")
  end

  it "gives a hint the way the chosen rule does" do
    expect(described_class.hint("min", "list_overlap")).to eq("Leave blank to require a perfect score.")
    expect(described_class.hint("min", "length_bounds")).to eq("Leave blank for no minimum.")
    expect(described_class.hint("max")).to eq("Leave blank for no maximum.")
  end

  it "shows a compare_to or score_by value in words and passes anything else through" do
    expect(described_class.value("compare_to", "expected")).to eq("Each row's expected value")
    expect(described_class.value("score_by", "made_up")).to eq("made_up")
    expect(described_class.value("value", "TOKEN")).to eq("TOKEN")
    expect(described_class.worded?("score_by")).to be(true)
    expect(described_class.worded?("value")).to be(false)
  end

  it "orders a config's keys the way the form lays them out" do
    config = { "trim" => true, "value" => "x", "compare_to" => "constant", "target_path" => "a", "mystery" => 1 }
    expect(described_class.in_form_order(config).keys).to eq(%w[target_path compare_to value trim mystery])
  end
end

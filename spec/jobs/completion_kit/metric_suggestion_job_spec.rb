require "rails_helper"

RSpec.describe CompletionKit::MetricSuggestionJob do
  let(:metric) { create(:completion_kit_metric) }

  before { CompletionKit::MetricVersion.ensure_current_for(metric) }

  it "generates a draft, validates it, and stores the summary on the draft" do
    variant = CompletionKit::MetricVariantGenerator::Variant.new(reasoning: "r", instruction: "tighter", rubric_bands: nil)
    allow_any_instance_of(CompletionKit::MetricVariantGenerator).to receive(:call).and_return([variant])
    allow_any_instance_of(CompletionKit::MetricImprovementValidator).to receive(:call).and_return({ "after" => 3, "before" => 1, "total" => 4 })

    expect { described_class.new.perform(metric.id) }
      .to change { CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "suggestion").count }.by(1)

    draft = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "suggestion").last
    expect(draft.validation_summary).to eq({ "after" => 3, "before" => 1, "total" => 4 })
  end

  it "broadcasts a ready status when a draft is produced" do
    variant = CompletionKit::MetricVariantGenerator::Variant.new(reasoning: "r", instruction: "tighter", rubric_bands: nil)
    allow_any_instance_of(CompletionKit::MetricVariantGenerator).to receive(:call).and_return([variant])
    allow_any_instance_of(CompletionKit::MetricImprovementValidator).to receive(:call).and_return({ "after" => 3 })

    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .with("metric_#{metric.id}_suggestion", hash_including(target: "ck-suggestion-status-#{metric.id}"))

    described_class.new.perform(metric.id)
  end

  it "does nothing when the metric does not exist" do
    expect(Turbo::StreamsChannel).not_to receive(:broadcast_replace_to)
    expect { described_class.new.perform(0) }.not_to change { CompletionKit::MetricVersion.count }
  end

  it "broadcasts a failure status when the model returns no usable variant" do
    allow_any_instance_of(CompletionKit::MetricVariantGenerator).to receive(:call).and_return([])
    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .with("metric_#{metric.id}_suggestion", hash_including(target: "ck-suggestion-status-#{metric.id}"))
    expect { described_class.new.perform(metric.id) }
      .not_to change { CompletionKit::MetricVersion.drafts.where(metric_id: metric.id).count }
  end

  it "broadcasts the failure status and does not raise when generation errors" do
    allow_any_instance_of(CompletionKit::MetricVariantGenerator).to receive(:call).and_raise(StandardError, "boom")
    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .with("metric_#{metric.id}_suggestion", hash_including(target: "ck-suggestion-status-#{metric.id}"))
    expect { described_class.perform_now(metric.id) }.not_to raise_error
  end

  it "does nothing for a check metric" do
    check_metric = create(:completion_kit_metric, :check)
    CompletionKit::MetricVersion.ensure_current_for(check_metric)
    expect(CompletionKit::MetricVariantGenerator).not_to receive(:new)
    expect(Turbo::StreamsChannel).not_to receive(:broadcast_replace_to)
    expect { described_class.new.perform(check_metric.id) }
      .not_to change { CompletionKit::MetricVersion.drafts.where(metric_id: check_metric.id).count }
  end

  it "replaces an existing suggestion draft" do
    old = CompletionKit::MetricVersion.create!(metric: metric, instruction: "old", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
    variant = CompletionKit::MetricVariantGenerator::Variant.new(reasoning: "r", instruction: "tighter", rubric_bands: nil)
    allow_any_instance_of(CompletionKit::MetricVariantGenerator).to receive(:call).and_return([variant])
    allow_any_instance_of(CompletionKit::MetricImprovementValidator).to receive(:call).and_return({ "after" => 1 })

    described_class.new.perform(metric.id)

    expect(CompletionKit::MetricVersion.exists?(old.id)).to be(false)
    expect(CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "suggestion").count).to eq(1)
  end
end

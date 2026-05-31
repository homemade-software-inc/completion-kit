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
end

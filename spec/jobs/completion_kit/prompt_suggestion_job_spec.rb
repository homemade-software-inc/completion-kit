require "rails_helper"

RSpec.describe CompletionKit::PromptSuggestionJob do
  let(:run) { create(:completion_kit_run) }

  def pending_suggestion
    create(:completion_kit_suggestion, run: run, prompt: run.prompt,
      status: "pending", suggested_template: nil, reasoning: nil)
  end

  def stub_service(suggested_template:, reasoning: "tighter")
    service = instance_double(CompletionKit::PromptImprovementService,
      suggest: {
        "reasoning" => reasoning,
        "suggested_template" => suggested_template,
        "original_template" => run.prompt.template
      })
    allow(CompletionKit::PromptImprovementService).to receive(:new).and_return(service)
  end

  it "drafts a rewrite, validates it, stores the summary, and marks it ready" do
    suggestion = pending_suggestion
    stub_service(suggested_template: "Summarize {{content}} crisply")
    summary = { "before_avg" => 3.0, "after_avg" => 4.0, "improved" => 2, "regressed" => 0,
                "unchanged" => 1, "tested" => 3, "capped" => false, "rows" => [] }
    allow(CompletionKit::PromptImprovementValidator).to receive(:new)
      .and_return(instance_double(CompletionKit::PromptImprovementValidator, call: summary))

    described_class.new.perform(suggestion.id)

    suggestion.reload
    expect(suggestion).to be_ready
    expect(suggestion.suggested_template).to eq("Summarize {{content}} crisply")
    expect(suggestion.validation_summary).to eq(summary)
  end

  it "broadcasts the ready state to the suggestion stream" do
    suggestion = pending_suggestion
    stub_service(suggested_template: "Summarize {{content}} better")
    allow(CompletionKit::PromptImprovementValidator).to receive(:new)
      .and_return(instance_double(CompletionKit::PromptImprovementValidator, call: { "tested" => 0, "capped" => false }))

    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .with("completion_kit_suggestion_#{suggestion.id}", hash_including(target: "ck-suggestion-status-#{suggestion.id}"))

    described_class.new.perform(suggestion.id)
  end

  it "marks the suggestion failed when the model returns no rewrite" do
    suggestion = pending_suggestion
    stub_service(suggested_template: "", reasoning: nil)

    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    described_class.new.perform(suggestion.id)

    expect(suggestion.reload).to be_failed
  end

  it "marks the suggestion failed and does not raise when drafting errors" do
    suggestion = pending_suggestion
    allow(CompletionKit::PromptImprovementService).to receive(:new).and_raise(StandardError, "boom")

    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    expect { described_class.perform_now(suggestion.id) }.not_to raise_error

    expect(suggestion.reload).to be_failed
  end

  it "does nothing when the suggestion no longer exists" do
    expect(Turbo::StreamsChannel).not_to receive(:broadcast_replace_to)
    expect { described_class.new.perform(0) }.not_to raise_error
  end

  it "swallows an error raised before the suggestion is loaded" do
    allow(CompletionKit::Suggestion).to receive(:find_by).and_raise(StandardError, "db down")
    expect(Turbo::StreamsChannel).not_to receive(:broadcast_replace_to)
    expect { described_class.perform_now(123) }.not_to raise_error
  end
end

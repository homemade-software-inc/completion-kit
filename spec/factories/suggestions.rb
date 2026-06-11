FactoryBot.define do
  factory :completion_kit_suggestion, class: "CompletionKit::Suggestion" do
    association :run, factory: :completion_kit_run
    prompt { run.prompt }
    original_template { "Summarize {{content}}" }
    suggested_template { "Summarize {{content}} clearly" }
    reasoning { "Tightened the instruction." }
    status { "ready" }
  end
end

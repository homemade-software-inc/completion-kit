FactoryBot.define do
  factory :completion_kit_test_run, class: "CompletionKit::TestRun" do
    association :prompt, factory: :completion_kit_prompt
    name { "Regression batch" }
    csv_data do
      <<~CSV
        content,audience,expected_output
        "Release notes","developers","A developer-focused summary"
      CSV
    end
    status { "draft" }
  end
end

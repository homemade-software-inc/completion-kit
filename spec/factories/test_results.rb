FactoryBot.define do
  factory :completion_kit_test_result, class: "CompletionKit::TestResult" do
    association :test_run, factory: :completion_kit_test_run
    status { "completed" }
    input_data { { content: "Release notes", audience: "developers" }.to_json }
    output_text { "A generated summary" }
    expected_output { "A developer-focused summary" }
    quality_score { 4.0 }
  end
end

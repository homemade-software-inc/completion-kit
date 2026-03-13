FactoryBot.define do
  factory :completion_kit_response, class: "CompletionKit::Response" do
    association :run, factory: :completion_kit_run
    input_data { { content: "Release notes", audience: "developers" }.to_json }
    response_text { "A generated summary" }
    expected_output { "A developer-focused summary" }
  end
end

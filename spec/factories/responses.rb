FactoryBot.define do
  factory :completion_kit_response, class: "CompletionKit::Response" do
    association :run, factory: :completion_kit_run
    input_data { { content: "Release notes", audience: "developers" }.to_json }
    response_text { "A generated summary" }
    expected_output { "A developer-focused summary" }
    status { "succeeded" }

    trait :pending do
      status { "pending" }
      response_text { nil }
    end

    trait :retrying do
      status { "retrying" }
      response_text { nil }
      attempts { 2 }
    end

    trait :failed do
      status { "failed" }
      response_text { nil }
      error_provider { "openai" }
      error_class { "Faraday::TimeoutError" }
      error_status { nil }
      error_message { "execution expired" }
      attempts { 5 }
    end
  end
end

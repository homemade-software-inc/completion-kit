FactoryBot.define do
  factory :completion_kit_dataset, class: "CompletionKit::Dataset" do
    sequence(:name) { |n| "Dataset #{n}" }
    csv_data do
      <<~CSV
        content,audience,expected_output
        "Release notes","developers","A developer-focused summary"
      CSV
    end
  end
end

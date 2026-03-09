require "csv"
require "json"

CompletionKit::TestResultMetricAssessment.delete_all
CompletionKit::TestResult.delete_all
CompletionKit::TestRun.delete_all
CompletionKit::Prompt.delete_all
CompletionKit::MetricGroupMembership.delete_all
CompletionKit::MetricGroup.delete_all
CompletionKit::Metric.delete_all

def csv_from_rows(rows)
  CSV.generate do |csv|
    csv << rows.first.keys
    rows.each do |row|
      csv << row.values
    end
  end
end

def create_metric(name:, description:, guidance_text:)
  CompletionKit::Metric.create!(
    name: name,
    description: description,
    guidance_text: guidance_text
  )
end

def create_metric_group(name:, description:, metrics:)
  metric_group = CompletionKit::MetricGroup.create!(name: name, description: description)

  metrics.each_with_index do |metric, index|
    metric_group.metric_group_memberships.create!(metric: metric, position: index + 1)
  end

  metric_group
end

def create_prompt(name:, description:, template:, model:, metric_group:)
  CompletionKit::Prompt.create!(
    name: name,
    description: description,
    template: template,
    llm_model: model,
    assessment_model: model,
    metric_group: metric_group
  )
end

def create_run(prompt:, name:, description:, status:, rows:)
  CompletionKit::TestRun.create!(
    prompt: prompt,
    name: name,
    description: description,
    status: status,
    csv_data: csv_from_rows(rows)
  )
end

def seed_result(test_run:, row:, output_text:, quality_score:, judge_feedback:)
  result = test_run.test_results.create!(
    status: quality_score ? "evaluated" : "completed",
    input_data: row.to_json,
    output_text: output_text,
    expected_output: row["expected_output"],
    quality_score: quality_score,
    judge_feedback: judge_feedback
  )

  return result if quality_score.nil?

  test_run.prompt.assessment_metrics.each_with_index do |metric, index|
    metric_score = [[quality_score - (index * 0.5), 1.0].max, 10.0].min.round(1)

    result.metric_assessments.create!(
      metric: metric,
      metric_name: metric.name,
      guidance_text: metric.guidance_text,
      rubric_text: metric.rubric_text,
      status: "evaluated",
      ai_score: metric_score,
      ai_feedback: "#{metric.name}: #{judge_feedback}"
    )
  end

  result
end

helpfulness = create_metric(
  name: "Helpfulness",
  description: "Checks whether the answer is useful to the reader.",
  guidance_text: "Reward clear summaries, practical next steps, and a response that saves the support team time."
)

accuracy = create_metric(
  name: "Accuracy",
  description: "Checks whether the answer preserves the important facts from the input.",
  guidance_text: "Reward factual accuracy, correct severity, and whether the customer impact is preserved."
)

support_review = create_metric_group(
  name: "Support review",
  description: "Use these metrics when reviewing support ticket summaries.",
  metrics: [helpfulness, accuracy]
)

support_prompt = create_prompt(
  name: "Support summary",
  description: "Turn a raw support ticket into a short internal summary.",
  template: <<~TEMPLATE,
    Summarize this support ticket for the support team.

    Customer:
    {{customer}}

    Problem:
    {{issue}}

    Severity:
    {{severity}}

    Return:
    - a one sentence summary
    - the customer impact
    - the next action
  TEMPLATE
  model: "gpt-4.1",
  metric_group: support_review
)

draft_rows = [
  {
    "customer" => "Acme Co",
    "issue" => "Users cannot reset their passwords from the login page.",
    "severity" => "high",
    "expected_output" => "Acme Co cannot reset passwords. This blocks sign-in for affected users. Investigate the reset flow and confirm a workaround."
  },
  {
    "customer" => "Northwind",
    "issue" => "Exports fail when the account has more than 10,000 rows.",
    "severity" => "medium",
    "expected_output" => "Northwind cannot export large datasets. Reporting work is delayed. Check the export job limit and confirm whether the job can be retried."
  },
  {
    "customer" => "Blue Sky",
    "issue" => "Duplicate invoices appeared after a subscription change.",
    "severity" => "high",
    "expected_output" => "Blue Sky saw duplicate invoices after a subscription change. Billing trust is affected. Review the billing event and correct the duplicate charge."
  }
]

scored_rows = [
  {
    "customer" => "Acme Co",
    "issue" => "Users cannot reset their passwords from the login page.",
    "severity" => "high",
    "expected_output" => "Acme Co cannot reset passwords. This blocks sign-in for affected users. Investigate the reset flow and confirm a workaround."
  },
  {
    "customer" => "Northwind",
    "issue" => "Exports fail when the account has more than 10,000 rows.",
    "severity" => "medium",
    "expected_output" => "Northwind cannot export large datasets. Reporting work is delayed. Check the export job limit and confirm whether the job can be retried."
  },
  {
    "customer" => "Blue Sky",
    "issue" => "Duplicate invoices appeared after a subscription change.",
    "severity" => "high",
    "expected_output" => "Blue Sky saw duplicate invoices after a subscription change. Billing trust is affected. Review the billing event and correct the duplicate charge."
  },
  {
    "customer" => "Delta Health",
    "issue" => "A SAML login loop sends users back to the sign-in screen.",
    "severity" => "urgent",
    "expected_output" => "Delta Health is stuck in a SAML login loop. Users cannot access the app. Check the SAML callback flow and provide an immediate workaround."
  }
]

draft_run = create_run(
  prompt: support_prompt,
  name: "Support dataset",
  description: "Small dataset for trying the full flow by hand.",
  status: "draft",
  rows: draft_rows
)

scored_run = create_run(
  prompt: support_prompt,
  name: "Support scored examples",
  description: "A few pre-scored results so the review screens make sense immediately.",
  status: "evaluated",
  rows: scored_rows
)

seed_result(
  test_run: scored_run,
  row: scored_rows[0],
  output_text: "Acme Co cannot reset passwords. Sign-in is blocked for affected users. Check the reset flow and provide a workaround.",
  quality_score: 9.4,
  judge_feedback: "Clear, accurate, and immediately useful."
)

seed_result(
  test_run: scored_run,
  row: scored_rows[1],
  output_text: "Northwind has export trouble with large accounts. The team should inspect the export job.",
  quality_score: 7.3,
  judge_feedback: "Mostly right, but it leaves out some business impact and detail."
)

seed_result(
  test_run: scored_run,
  row: scored_rows[2],
  output_text: "There was a billing issue after a plan change.",
  quality_score: 5.6,
  judge_feedback: "Related to the issue, but too vague to be useful."
)

seed_result(
  test_run: scored_run,
  row: scored_rows[3],
  output_text: "Users are seeing a SAML login loop and cannot get into the app. Check the SAML callback and give the customer an immediate workaround.",
  quality_score: 9.0,
  judge_feedback: "Accurate and high urgency. Good internal summary."
)

draft_run.update!(status: "draft")
scored_run.update!(status: "evaluated")

puts "Seeded #{CompletionKit::Prompt.count} prompt"
puts "Seeded #{CompletionKit::Metric.count} metrics"
puts "Seeded #{CompletionKit::MetricGroup.count} metric group"
puts "Seeded #{CompletionKit::TestRun.count} runs"
puts "Seeded #{CompletionKit::TestResult.count} results"

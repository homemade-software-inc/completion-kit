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

accuracy = CompletionKit::Metric.create!(
  name: "Accuracy",
  description: "Does the output preserve every important fact from the input?",
  guidance_text: "Penalize missing facts, wrong numbers, invented details, or swapped severity levels. A single factual error drops the score below 7."
)

clarity = CompletionKit::Metric.create!(
  name: "Clarity",
  description: "Is the output concise, scannable, and free of filler?",
  guidance_text: "Reward short sentences, bullet points, and plain language. Penalize jargon, hedging ('it seems like'), and unnecessary preamble."
)

actionability = CompletionKit::Metric.create!(
  name: "Actionability",
  description: "Does the output tell the reader exactly what to do next?",
  guidance_text: "The output must include a concrete next step. Vague suggestions like 'look into it' score below 5."
)

support_metrics = CompletionKit::MetricGroup.create!(name: "Support quality", description: "Score support ticket summaries on accuracy, clarity, and actionability.")
support_metrics.metric_group_memberships.create!(metric: accuracy, position: 1)
support_metrics.metric_group_memberships.create!(metric: clarity, position: 2)
support_metrics.metric_group_memberships.create!(metric: actionability, position: 3)

prompt_v1 = CompletionKit::Prompt.create!(
  name: "Ticket summarizer",
  description: "Turn a raw support ticket into a short internal summary with next steps.",
  template: <<~TEMPLATE,
    Summarize this support ticket for the internal team.

    Customer: {{customer}}
    Problem: {{issue}}
    Severity: {{severity}}

    Return:
    - One-sentence summary
    - Customer impact
    - Recommended next action
  TEMPLATE
  llm_model: "gpt-4.1",
  assessment_model: "gpt-4.1",
  metric_group: support_metrics,
  family_key: "ticket-summarizer",
  version_number: 1,
  current: false,
  published_at: 2.days.ago
)

prompt_v2 = CompletionKit::Prompt.create!(
  name: "Ticket summarizer",
  description: "v2: Added severity context and tone guidance.",
  template: <<~TEMPLATE,
    You are an internal support analyst. Summarize this ticket in three bullet points.

    Customer: {{customer}}
    Problem: {{issue}}
    Severity: {{severity}}

    Rules:
    - First bullet: one-sentence summary including the customer name
    - Second bullet: who is affected and how badly
    - Third bullet: the single most important next action (be specific)
    - If severity is urgent or high, say so explicitly
    - No hedging, no filler, no preamble
  TEMPLATE
  llm_model: "gpt-4.1",
  assessment_model: "gpt-4.1",
  metric_group: support_metrics,
  family_key: "ticket-summarizer",
  version_number: 2,
  current: true,
  published_at: Time.current
)

tickets = [
  {
    "customer" => "Acme Corp",
    "issue" => "Users cannot reset their passwords from the login page. The reset email never arrives. Affects all users on the enterprise plan. Started after last night's deploy.",
    "severity" => "high",
    "expected_output" => "Acme Corp users cannot reset passwords — reset emails are not sending. All enterprise-plan users are locked out if they forget credentials. Investigate the email service integration deployed last night and confirm a workaround."
  },
  {
    "customer" => "Northwind Trading",
    "issue" => "CSV exports fail silently when the account has more than 10,000 rows. The download button spins indefinitely. Two account managers have reported this in the last week.",
    "severity" => "medium",
    "expected_output" => "Northwind's CSV exports fail for datasets over 10K rows — the download hangs with no error. Account managers cannot pull reports for large clients. Investigate the export job's row limit and add a timeout or pagination fix."
  },
  {
    "customer" => "Blue Sky Airlines",
    "issue" => "Duplicate invoices appeared after a mid-cycle plan upgrade. The customer was charged twice for the same period. Finance team flagged it.",
    "severity" => "high",
    "expected_output" => "Blue Sky was double-charged after a mid-cycle plan upgrade — two invoices cover the same billing period. Customer trust and revenue recognition are at risk. Review the billing event log, void the duplicate, and issue a credit."
  },
  {
    "customer" => "Delta Health",
    "issue" => "SAML SSO login enters an infinite redirect loop. Users see the login page flash and reload repeatedly. IT admin confirmed the SAML certificate is valid. 800+ employees cannot access the platform.",
    "severity" => "urgent",
    "expected_output" => "Delta Health's 800+ employees are locked out by a SAML redirect loop. The SSO certificate is valid, so the issue is likely in the callback handler. Escalate immediately, check the SAML assertion consumer URL, and provide a direct-login bypass."
  },
  {
    "customer" => "Greenleaf Organics",
    "issue" => "Dashboard charts show yesterday's data instead of today's. The data pipeline last ran successfully at 2am but the cache seems stale. Only affects the analytics tab.",
    "severity" => "low",
    "expected_output" => "Greenleaf's dashboard charts are showing stale data (yesterday instead of today). The pipeline ran at 2am but the analytics cache was not invalidated. Clear the analytics cache and verify the cache-bust trigger is firing after pipeline completion."
  }
]

v1_run = CompletionKit::TestRun.create!(
  prompt: prompt_v1,
  name: "v1 baseline",
  description: "First run with the basic prompt. Scores are decent but the outputs are vague.",
  status: "evaluated",
  csv_data: csv_from_rows(tickets)
)

v1_outputs = [
  {
    text: "Acme Corp has a password reset issue. Users can't reset their passwords. The team should look into the email system.",
    scores: { "Accuracy" => 7.2, "Clarity" => 6.8, "Actionability" => 4.5 },
    feedback: {
      "Accuracy" => "Captures the core issue but omits that it affects enterprise-plan users and was caused by a deploy.",
      "Clarity" => "Readable but generic. 'Has a password reset issue' is not specific enough for triage.",
      "Actionability" => "'Look into the email system' is too vague. Does not mention the deploy or suggest a specific investigation path."
    }
  },
  {
    text: "Northwind has export problems with large accounts. The team should check the export feature.",
    scores: { "Accuracy" => 6.0, "Clarity" => 5.5, "Actionability" => 3.8 },
    feedback: {
      "Accuracy" => "Mentions large accounts but drops the 10K row threshold, the silent failure mode, and the spinner behavior.",
      "Clarity" => "'Export problems' is vague. A reader cannot tell if exports error out, hang, or produce wrong data.",
      "Actionability" => "'Check the export feature' gives no direction. Should mention row limits, timeouts, or pagination."
    }
  },
  {
    text: "There was a billing issue at Blue Sky Airlines after a plan change. Someone should review it.",
    scores: { "Accuracy" => 4.8, "Clarity" => 4.2, "Actionability" => 3.0 },
    feedback: {
      "Accuracy" => "Misses that it was a duplicate charge, that it was mid-cycle, and that finance flagged it.",
      "Clarity" => "'Billing issue' and 'plan change' are too vague to act on. Does not say what went wrong.",
      "Actionability" => "'Someone should review it' is not actionable. No mention of voiding the duplicate or issuing a credit."
    }
  },
  {
    text: "Delta Health users are experiencing login problems with SAML. The issue needs to be investigated. This is urgent.",
    scores: { "Accuracy" => 6.5, "Clarity" => 5.0, "Actionability" => 4.0 },
    feedback: {
      "Accuracy" => "Mentions SAML and urgency but drops the redirect loop detail, the 800+ user count, and the valid certificate.",
      "Clarity" => "'Login problems' understates the severity. Should say 'locked out' or 'redirect loop'.",
      "Actionability" => "'Needs to be investigated' is generic. Should suggest checking the callback URL or providing a bypass."
    }
  },
  {
    text: "Greenleaf's dashboard is showing old data. The data pipeline might be the cause. Low priority.",
    scores: { "Accuracy" => 6.8, "Clarity" => 6.0, "Actionability" => 4.2 },
    feedback: {
      "Accuracy" => "Gets the gist but misses that only the analytics tab is affected and that the pipeline did run successfully.",
      "Clarity" => "'Old data' is imprecise — should say 'yesterday's data' vs today's.",
      "Actionability" => "'Might be the cause' hedges. Should point to the cache layer and suggest clearing it."
    }
  }
]

v1_outputs.each_with_index do |output, idx|
  result = v1_run.test_results.create!(
    status: "evaluated",
    input_data: tickets[idx].to_json,
    output_text: output[:text],
    expected_output: tickets[idx]["expected_output"],
    quality_score: output[:scores].values.sum / output[:scores].size.to_f,
    judge_feedback: output[:feedback].map { |metric, fb| "#{metric}: #{fb}" }.join("\n\n")
  )

  output[:scores].each do |metric_name, score|
    metric = CompletionKit::Metric.find_by!(name: metric_name)
    result.metric_assessments.create!(
      metric: metric,
      metric_name: metric_name,
      guidance_text: metric.guidance_text,
      rubric_text: metric.rubric_text,
      status: "evaluated",
      ai_score: score,
      ai_feedback: output[:feedback][metric_name]
    )
  end
end

v2_run = CompletionKit::TestRun.create!(
  prompt: prompt_v2,
  name: "v2 improved",
  description: "Same dataset, better prompt. Scores jumped across every metric.",
  status: "evaluated",
  csv_data: csv_from_rows(tickets)
)

v2_outputs = [
  {
    text: "- Acme Corp enterprise users cannot reset passwords — reset emails stopped sending after last night's deploy.\n- All enterprise-plan users are locked out if they forget or need to change credentials.\n- Investigate the email service changes in last night's deploy; confirm whether a rollback or manual reset workaround is available.",
    scores: { "Accuracy" => 9.5, "Clarity" => 9.2, "Actionability" => 9.0 },
    feedback: {
      "Accuracy" => "Captures every key detail: enterprise plan, reset emails not sending, deploy timing.",
      "Clarity" => "Three clean bullets. No filler. Each bullet has one job.",
      "Actionability" => "Points to the specific deploy, suggests rollback or workaround. Concrete."
    }
  },
  {
    text: "- Northwind CSV exports fail silently for datasets over 10,000 rows — the download spinner hangs indefinitely.\n- Two account managers cannot pull client reports, blocking their weekly workflow.\n- Check the export job's row limit, add a server-side timeout, and consider paginated exports for large accounts.",
    scores: { "Accuracy" => 9.3, "Clarity" => 9.0, "Actionability" => 9.4 },
    feedback: {
      "Accuracy" => "Includes the 10K threshold, silent failure, and spinner behavior. All facts preserved.",
      "Clarity" => "Specific numbers and behavior. A reader knows exactly what's happening.",
      "Actionability" => "Three concrete steps: check limit, add timeout, consider pagination. Excellent."
    }
  },
  {
    text: "- Blue Sky Airlines was double-charged after a mid-cycle plan upgrade — two invoices cover the same billing period.\n- Customer trust and revenue recognition are at risk; finance has already flagged the discrepancy.\n- Review the billing event log for the upgrade, void the duplicate invoice, and issue a credit to the customer.",
    scores: { "Accuracy" => 9.6, "Clarity" => 9.4, "Actionability" => 9.5 },
    feedback: {
      "Accuracy" => "Every detail preserved: duplicate charge, mid-cycle, same period, finance flagged it.",
      "Clarity" => "Precise language. 'Double-charged' is unambiguous. Impact is clear.",
      "Actionability" => "Three-step resolution: review log, void duplicate, issue credit. Ready to execute."
    }
  },
  {
    text: "- URGENT: Delta Health's 800+ employees are locked out by a SAML SSO redirect loop. Certificate is confirmed valid.\n- The entire organization cannot access the platform — this is a total outage for the customer.\n- Escalate immediately. Check the SAML assertion consumer URL for mismatches and provide a direct-login bypass while investigating.",
    scores: { "Accuracy" => 9.8, "Clarity" => 9.5, "Actionability" => 9.7 },
    feedback: {
      "Accuracy" => "All facts: 800+ users, redirect loop, valid cert, total lockout. Nothing missed.",
      "Clarity" => "URGENT prefix matches severity. Impact is stark and clear.",
      "Actionability" => "Escalate + check assertion URL + provide bypass. Specific, ordered, and immediate."
    }
  },
  {
    text: "- Greenleaf's analytics dashboard is showing yesterday's data instead of today's. Only the analytics tab is affected.\n- The data pipeline completed successfully at 2am, so the issue is likely a stale cache rather than a pipeline failure.\n- Clear the analytics cache and verify the cache-invalidation trigger fires after each pipeline run.",
    scores: { "Accuracy" => 9.4, "Clarity" => 9.1, "Actionability" => 9.3 },
    feedback: {
      "Accuracy" => "Distinguishes 'yesterday vs today', scopes to analytics tab, notes pipeline ran OK. Complete.",
      "Clarity" => "Identifies the root cause (cache vs pipeline). Reader knows where to look.",
      "Actionability" => "Two steps: clear cache, fix the trigger. No guesswork."
    }
  }
]

v2_outputs.each_with_index do |output, idx|
  result = v2_run.test_results.create!(
    status: "evaluated",
    input_data: tickets[idx].to_json,
    output_text: output[:text],
    expected_output: tickets[idx]["expected_output"],
    quality_score: output[:scores].values.sum / output[:scores].size.to_f,
    judge_feedback: output[:feedback].map { |metric, fb| "#{metric}: #{fb}" }.join("\n\n")
  )

  output[:scores].each do |metric_name, score|
    metric = CompletionKit::Metric.find_by!(name: metric_name)
    result.metric_assessments.create!(
      metric: metric,
      metric_name: metric_name,
      guidance_text: metric.guidance_text,
      rubric_text: metric.rubric_text,
      status: "evaluated",
      ai_score: score,
      ai_feedback: output[:feedback][metric_name]
    )
  end
end

draft_run = CompletionKit::TestRun.create!(
  prompt: prompt_v2,
  name: "New batch (draft)",
  description: "Ready to run — generate outputs to see how v2 handles fresh data.",
  status: "draft",
  csv_data: csv_from_rows([
    {
      "customer" => "Pinnacle Finance",
      "issue" => "Two-factor authentication codes are arriving 5 minutes late. Users are locked out during the delay window.",
      "severity" => "high",
      "expected_output" => "Pinnacle users are locked out because 2FA codes arrive ~5 minutes late. Check the SMS provider's delivery latency and consider extending the code validity window as an interim fix."
    },
    {
      "customer" => "Redwood Labs",
      "issue" => "The search index has not updated in 3 days. New documents are invisible to users. Reindexing manually fixes it temporarily.",
      "severity" => "medium",
      "expected_output" => "Redwood's search index is 3 days stale — new documents are not findable. Manual reindex works as a stopgap. Investigate why the automatic index job stopped running and restart it."
    }
  ])
)

puts "Created #{CompletionKit::Prompt.count} prompts (2 versions of the same prompt)"
puts "Created #{CompletionKit::Metric.count} metrics in #{CompletionKit::MetricGroup.count} group"
puts "Created #{CompletionKit::TestRun.count} runs (v1 baseline, v2 improved, 1 draft)"
puts "Created #{CompletionKit::TestResult.count} scored results with #{CompletionKit::TestResultMetricAssessment.count} metric assessments"
puts ""
puts "The story: v1 averaged ~5.3 across metrics. v2 averages ~9.4."
puts "Open the UI to see the version comparison and per-metric breakdowns."

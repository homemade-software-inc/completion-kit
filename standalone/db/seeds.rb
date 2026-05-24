CompletionKit::ProviderCredential.skip_callback(:save, :after, :enqueue_discovery)

[
  { provider: "openai", api_key: ENV["OPENAI_API_KEY"] || "sk-seed-placeholder" },
  { provider: "anthropic", api_key: ENV["ANTHROPIC_API_KEY"] || "sk-ant-seed-placeholder" }
].each do |attrs|
  CompletionKit::ProviderCredential.find_or_create_by!(provider: attrs[:provider]) do |pc|
    pc.api_key = attrs[:api_key]
  end
end

CompletionKit::ProviderCredential.set_callback(:save, :after, :enqueue_discovery)

models = [
  { provider: "openai", model_id: "gpt-5.4-mini", display_name: "GPT-5.4 Mini", status: "active", supports_generation: true, supports_judging: true, probed_at: Time.current, discovered_at: Time.current },
  { provider: "openai", model_id: "gpt-4.1-mini", display_name: "GPT-4.1 Mini", status: "active", supports_generation: true, supports_judging: true, probed_at: Time.current, discovered_at: Time.current },
  { provider: "openai", model_id: "gpt-4o-mini", display_name: "GPT-4o Mini", status: "active", supports_generation: true, supports_judging: true, probed_at: Time.current, discovered_at: Time.current },
  { provider: "anthropic", model_id: "claude-sonnet-4-6", display_name: "Claude Sonnet 4.6", status: "active", supports_generation: true, supports_judging: true, probed_at: Time.current, discovered_at: Time.current },
  { provider: "anthropic", model_id: "claude-haiku-4-5", display_name: "Claude Haiku 4.5", status: "active", supports_generation: true, supports_judging: true, probed_at: Time.current, discovered_at: Time.current }
]

models.each do |attrs|
  CompletionKit::Model.find_or_create_by!(provider: attrs[:provider], model_id: attrs[:model_id]) do |m|
    m.assign_attributes(attrs)
  end
end

tone = CompletionKit::Metric.find_or_create_by!(name: "Tone") do |m|
  m.instruction = "Is the reply professional and warm? It should feel like it was written by a thoughtful human who read the ticket, not a deflection script."
  m.rubric_bands = [
    { "stars" => 5, "description" => "Acknowledges the customer's situation in a way that feels human. Confident, measured, never defensive. Reads like a senior support engineer who actually cares." },
    { "stars" => 4, "description" => "Professional and warm enough. One slightly stock phrase but nothing that undermines trust." },
    { "stars" => 3, "description" => "Serviceable but neutral. Hits the marks without warmth. The kind of reply a customer would tolerate, not appreciate." },
    { "stars" => 2, "description" => "Cold or formulaic. Reads like a template that wasn't customized. Missing the human touch the situation calls for." },
    { "stars" => 1, "description" => "Robotic, dismissive, or defensive. The customer would be more frustrated after reading this than before." }
  ]
end

helpfulness = CompletionKit::Metric.find_or_create_by!(name: "Helpfulness") do |m|
  m.instruction = "Does the reply move the case forward? It should answer the question, propose a concrete next step, or both."
  m.rubric_bands = [
    { "stars" => 5, "description" => "Resolves the question outright or gives the customer exactly what they need to act. No further back-and-forth required." },
    { "stars" => 4, "description" => "Addresses the core question with one minor gap (e.g. forgot to confirm a detail). Customer can act on it." },
    { "stars" => 3, "description" => "Partial answer. Customer will likely need to reply for clarification before they can move forward." },
    { "stars" => 2, "description" => "Deflects, asks for information already in the ticket, or stalls without committing to anything." },
    { "stars" => 1, "description" => "Unhelpful, off-topic, or contradicts what the customer asked for." }
  ]
end

accuracy = CompletionKit::Metric.find_or_create_by!(name: "Accuracy") do |m|
  m.instruction = "Are the factual claims and policy statements in the reply correct? It must not invent policies, prices, deadlines, or product features."
  m.rubric_bands = [
    { "stars" => 5, "description" => "Every factual claim is verifiable. Policies cited are real. Numbers, dates, and product behaviour all match what's known." },
    { "stars" => 4, "description" => "One minor embellishment or slightly soft claim, but nothing that would mislead the customer." },
    { "stars" => 3, "description" => "Mostly accurate but includes one detail that's questionable (e.g. cites a feature with the wrong limit, references a policy loosely)." },
    { "stars" => 2, "description" => "Multiple inaccuracies or invented details that could cause material confusion or future complaints." },
    { "stars" => 1, "description" => "Contradicts ticket facts, invents policies that don't exist, or commits the company to something it can't deliver." }
  ]
end

category_accuracy = CompletionKit::Metric.find_or_create_by!(name: "Category Accuracy") do |m|
  m.instruction = "Did the model assign the right intent category to this ticket? Categories include refund, shipping, promo_code, account_access, loyalty, churn_risk, product_question, complaint."
  m.rubric_bands = [
    { "stars" => 5, "description" => "Correct primary category, with a sensible secondary if the ticket has overlap (e.g. churn_risk + loyalty)." },
    { "stars" => 3, "description" => "Primary category is right but the model missed an obvious secondary signal." },
    { "stars" => 1, "description" => "Wrong category, or labelled it as 'other' when a specific category clearly applies." }
  ]
end

urgency_calibration = CompletionKit::Metric.find_or_create_by!(name: "Urgency Calibration") do |m|
  m.instruction = "Does the assigned urgency match the actual business and customer risk? Threats to dispute, churn signals, and outage language should all push urgency up."
  m.rubric_bands = [
    { "stars" => 5, "description" => "Urgency reflects both customer affect (frustration, threats to escalate) and business risk (revenue, public exposure). Hard to defend a different call." },
    { "stars" => 3, "description" => "Reasonable urgency, but a defensible argument exists for one tier higher or lower. Missed one calibration signal." },
    { "stars" => 1, "description" => "Off by two tiers. Misses obvious signals like 'I'm disputing with my bank' or 'we're evaluating alternatives'." }
  ]
end

confidence = CompletionKit::Metric.find_or_create_by!(name: "Confidence") do |m|
  m.instruction = "Is the model's confidence well-calibrated? It should hedge when the ticket is genuinely ambiguous and commit when it isn't."
  m.rubric_bands = [
    { "stars" => 5, "description" => "Confidence matches actual ambiguity. Hedges where the ticket is unclear; commits where it isn't. Never both confident and wrong." },
    { "stars" => 3, "description" => "Calibration is mostly right with one over- or under-confident call." },
    { "stars" => 1, "description" => "Overconfident on ambiguous tickets, or vague on clear ones. Confidence carries no signal." }
  ]
end

clarity = CompletionKit::Metric.find_or_create_by!(name: "Clarity") do |m|
  m.instruction = "Can a triage queue reader understand the ticket from this summary in one read? Plain language, no jargon clouds, no pronoun ambiguity."
  m.rubric_bands = [
    { "stars" => 5, "description" => "Instantly readable. A new support engineer would understand the case from this summary alone." },
    { "stars" => 3, "description" => "Clear but slightly stilted, or assumes context the reader might not have." },
    { "stars" => 1, "description" => "Confusing, requires re-reading, or omits a key noun." }
  ]
end

completeness = CompletionKit::Metric.find_or_create_by!(name: "Completeness") do |m|
  m.instruction = "Does the summary capture what matters: customer intent, the urgency hint (if any), and the one fact a triage agent needs to route the ticket?"
  m.rubric_bands = [
    { "stars" => 5, "description" => "Captures intent, urgency cue, and the routing-relevant fact. A triage agent can route confidently from this alone." },
    { "stars" => 3, "description" => "Gets the intent but misses one beat (urgency or routing fact)." },
    { "stars" => 1, "description" => "Misses what matters. The triage agent has to open the ticket to make any decision." }
  ]
end

brevity = CompletionKit::Metric.find_or_create_by!(name: "Brevity") do |m|
  m.instruction = "Is the summary 1-2 sentences and tightly written? It should fit a single line in a queue view without truncation."
  m.rubric_bands = [
    { "stars" => 5, "description" => "1-2 sentences. Every word earns its place. Reads as one unit." },
    { "stars" => 3, "description" => "Slightly over-length or includes a stock phrase that adds nothing." },
    { "stars" => 1, "description" => "Way too long, way too short, or compresses so hard it loses meaning." }
  ]
end

reply_metrics   = [tone, helpfulness, accuracy]
triage_metrics  = [category_accuracy, urgency_calibration, confidence]
summary_metrics = [clarity, completeness, brevity]

reply_group = CompletionKit::MetricGroup.find_or_create_by!(name: "Reply Quality") do |c|
  c.description = "Quality assessment for outbound customer support replies"
end
reply_metrics.each_with_index do |metric, i|
  CompletionKit::MetricGroupMembership.find_or_create_by!(metric_group: reply_group, metric: metric) do |cm|
    cm.position = i + 1
  end
end

triage_group = CompletionKit::MetricGroup.find_or_create_by!(name: "Triage Quality") do |c|
  c.description = "Assessment criteria for ticket triage classifications"
end
triage_metrics.each_with_index do |metric, i|
  CompletionKit::MetricGroupMembership.find_or_create_by!(metric_group: triage_group, metric: metric) do |cm|
    cm.position = i + 1
  end
end

summary_group = CompletionKit::MetricGroup.find_or_create_by!(name: "Summary Quality") do |c|
  c.description = "Assessment criteria for one-line ticket summaries in queue views"
end
summary_metrics.each_with_index do |metric, i|
  CompletionKit::MetricGroupMembership.find_or_create_by!(metric_group: summary_group, metric: metric) do |cm|
    cm.position = i + 1
  end
end

csv_data = <<~CSV
  ticket
  "Order #4827 was a Christmas gift for my mom. She's 78 and on dialysis. The dryer arrived with a dent on the front panel. I called within an hour, was told to email photos, did so, then heard nothing for 11 days. Today your support agent told me the return window has 'closed' and offered $40 in credit. I paid $749. I want a full refund or a replacement, not credit toward a future purchase. I'm planning to dispute with my bank by Friday if this isn't resolved."
  "Tracking on order #5102 says delivered to my front porch Tuesday at 3:47pm. I was home all day; nothing was delivered. Two of my neighbours have Ring cameras and neither shows a delivery van on our street. I've already filed a missing-package report on your site and got an automated reply. The order was a $315 KitchenAid stand mixer (wedding gift) and the wedding is Saturday. Can someone actually look at this today?"
  "I tried to use the WELCOME20 code at checkout and it says 'invalid'. The promo email says it's good through May 31. I've used the same email I'm signed in with. Cleared cookies, tried Chrome and Safari, same result. Did the code expire early, or am I missing something? Cart is sitting at $186 (kettle and a coffee grinder) waiting on you."
  "I can't sign into my account. The 2FA code text isn't arriving anymore. I've requested 4 codes in the last hour, my phone shows full bars, no SMS. Phone number on file is correct (I receive other texts fine). I have around $540 in store credit on the account from a return last month and I'd like to use it before it expires on June 15. Can you send a recovery code via email instead?"
  "I've been a Gold tier member since 2019. I just got the email about the program changes. Moving Gold to a $99/year fee from free, with the 10% loyalty discount dropping to 5%. I spend roughly $4,000/year with you and have for the last 6 years. I understand business is business but this is a meaningful change. Is there grandfather pricing for long-term members, or should I be looking at competitors?"
CSV

ticket_inputs = csv_data.lines[1..5].map { |line| line.strip.tr('"', "") }

dataset = CompletionKit::Dataset.find_or_create_by!(name: "Customer Tickets (sample)") do |d|
  d.csv_data = csv_data
end

reply_prompt = CompletionKit::Prompt.find_or_create_by!(name: "Support Reply Generator") do |p|
  p.description = "Drafts a customer support reply from a ticket and order context"
  p.template = "You are a senior customer support agent at an online retailer. Draft a reply to this customer ticket. Be warm, accurate, and propose a concrete next step. Under 200 words.\n\n{{ticket}}"
  p.llm_model = "gpt-4.1-mini"
end

triage_prompt = CompletionKit::Prompt.find_or_create_by!(name: "Ticket Triage") do |p|
  p.description = "Categorizes incoming tickets by intent and urgency for routing"
  p.template = "Classify this support ticket. Output: category (one of refund, shipping, promo_code, account_access, loyalty, churn_risk, product_question, complaint), urgency (low, medium, high, critical), and a one-sentence rationale. Format as JSON.\n\n{{ticket}}"
  p.llm_model = "gpt-4.1-mini"
end

summary_v1 = CompletionKit::Prompt.find_or_create_by!(name: "Ticket Summary", version_number: 1) do |p|
  p.description = "Generates a 1-2 sentence queue-view summary of an incoming ticket"
  p.template = "Write a 1-2 sentence summary of this ticket for a triage queue view. Capture intent, urgency hint, and the routing-relevant fact. No greeting or sign-off.\n\n{{ticket}}"
  p.llm_model = "claude-sonnet-4-6"
end
summary_family = summary_v1.family_key

summary_v2 = CompletionKit::Prompt.find_or_create_by!(family_key: summary_family, version_number: 2) do |p|
  p.name = "Ticket Summary"
  p.description = "Generates a 1-2 sentence queue-view summary of an incoming ticket"
  p.template = "Summarize this support ticket in one short line for a triage queue. Be as brief as possible.\n\n{{ticket}}"
  p.llm_model = "claude-sonnet-4-6"
  p.current = false
end

summary_v3 = CompletionKit::Prompt.find_or_create_by!(family_key: summary_family, version_number: 3) do |p|
  p.name = "Ticket Summary"
  p.description = "Generates a 1-2 sentence queue-view summary of an incoming ticket"
  p.template = "Write a 1-2 sentence summary of this ticket for a triage queue view. Capture the customer's intent, any urgency signal, and the one fact a triage agent needs to route it. Keep concrete numbers and IDs. No greeting or sign-off.\n\n{{ticket}}"
  p.llm_model = "claude-sonnet-4-6"
  p.current = false
end
summary_v3.publish! unless summary_v3.current?

reply_responses = [
  { input: ticket_inputs[0],
    text: "Hi. I'm so sorry this happened, especially given who the dryer was for. You did everything right: photos within the hour, then 11 days of silence on our end. That's on us, and the credit offer doesn't make it right.\n\nI've reviewed order #4827 and approved a full refund of $749 to your original payment method. You should see it within 3-5 business days. If you'd prefer a replacement instead, just reply to this email and I'll arrange a courier pickup of the damaged unit and a same-week dispatch of a new one.\n\nNo need to dispute with your bank. We'll handle this directly. I've also flagged the 11-day gap internally so we can figure out where the email got lost. Apologies again, and please pass our best wishes to your mom.",
    scores: { "Tone" => [5, "Genuinely warm without being saccharine. Acknowledges the human stakes (Christmas, mom on dialysis) and the company failure. Reads like a senior person who actually cares."],
              "Helpfulness" => [5, "Approves the refund outright, offers replacement as alternative, removes the bank dispute pressure, and commits to internal follow-up. Customer can act immediately."],
              "Accuracy" => [5, "Order number, amount, and refund timeline all match the ticket. No invented policies."] } },
  { input: ticket_inputs[1],
    text: "Thanks for the report. To investigate, can you confirm:\n\n1. The full delivery address on file\n2. The carrier the package shipped with\n3. Whether you have a signed delivery confirmation\n\nOnce I have those I can pull the tracking event log.",
    scores: { "Tone" => [3, "Cold and procedural. The customer is under wedding-deadline pressure and the reply doesn't acknowledge any of that."],
              "Helpfulness" => [2, "Asks for information already discoverable from the order. Delivery address is on file, carrier is in the tracking the customer already cited. This will frustrate them and burn a round-trip with the wedding looming."],
              "Accuracy" => [4, "What's stated is technically correct, but the questions treat the ticket as if half of it weren't read."] } },
  { input: ticket_inputs[2],
    text: "Great question. The WELCOME20 code is for first-time customers only, which is why it's coming back invalid (we can see you've ordered with us before). The promo email goes to our broader newsletter list and the eligibility wasn't called out clearly enough. I've flagged that with marketing.\n\nFor the cart you've got open ($186), I've issued a one-time 15% off code: THANKS-LOYAL-186. Apply it at checkout. Same constraints as WELCOME20 (not stackable with other promos), valid for the next 7 days. Reply if it doesn't apply cleanly and I'll reissue.",
    scores: { "Tone" => [4, "Friendly, owns the marketing copy gap, and lands the correction without being defensive."],
              "Helpfulness" => [5, "Explains the rejection, offers a real alternative discount on the same cart amount, and pre-empts the 'doesn't stack' question. Customer can complete the purchase immediately."],
              "Accuracy" => [5, "First-time-customer constraint matches our promo policy. Discount math is correct. No invented terms."] } },
  { input: ticket_inputs[3],
    text: "Hi. Sorry about the SMS issue. I've sent a one-time recovery code to the email on your account; please use it within the next 30 minutes to sign in.\n\nOnce you're back in, you can switch 2FA to an authenticator app under Security Settings. That path doesn't depend on SMS delivery, so this won't recur.\n\nGood news on the store credit: it doesn't actually expire on June 15. Store credits issued from returns are good for 24 months from issue. The June 15 date you saw was for a separate promotional credit balance. Happy to walk through both balances if helpful.",
    scores: { "Tone" => [4, "Calm and reassuring. The 'good news' framing on the credit lands well."],
              "Helpfulness" => [4, "Resolves the immediate sign-in problem and points at a permanent fix. The credit-policy detail is useful but slightly muddies the main thread."],
              "Accuracy" => [3, "The '24 months from issue' return-credit policy isn't verified. Agent should check before stating it as fact. Sending recovery code via email and pointing at authenticator-app 2FA are both correct."] } },
  { input: ticket_inputs[4],
    text: "Hi. Thank you for the long history with us, and for the candid feedback. Hearing this from a 2019 Gold member spending $4k a year carries real weight.\n\nThe Gold changes come from our cost structure (the free tier wasn't sustainable as the program grew) but I understand that doesn't change your math. For long-tenured members in your situation, I can offer a 12-month grandfather of the legacy benefits at no charge while we work out a longer-term path. You'd keep the 10% discount and free Gold status through next May.\n\nWould the grandfather year work as a stopgap? If so, I'll get it set up today.",
    scores: { "Tone" => [5, "Acknowledges the customer's history specifically. Empathetic without being defensive about the program change. Honest about the rationale."],
              "Helpfulness" => [4, "Offers a concrete stopgap (12-month grandfather) and frames the longer-term conversation. Doesn't address whether a paid tier might fit them better."],
              "Accuracy" => [4, "Grandfather offer needs retention sign-off before being committed to in writing. Otherwise grounded in standard retention plays."] } }
]

triage_responses = [
  { input: ticket_inputs[0],
    text: "{ \"category\": \"refund\", \"secondary\": \"complaint\", \"urgency\": \"critical\", \"rationale\": \"Customer is threatening a bank dispute by Friday and the case has already escalated through one failed handling.\" }",
    scores: { "Category Accuracy" => [5, "Refund is the primary correct call; complaint as secondary captures the 11-day no-response handling failure."],
              "Urgency Calibration" => [5, "Bank dispute threat plus 11-day delay plus emotional weight (Christmas gift for elderly parent) justifies critical."],
              "Confidence" => [5, "Committed where the ticket is clear, didn't hedge unnecessarily."] } },
  { input: ticket_inputs[1],
    text: "{ \"category\": \"shipping\", \"urgency\": \"high\", \"rationale\": \"Missing-package report on a wedding-deadline order.\" }",
    scores: { "Category Accuracy" => [5, "Shipping is the right primary. The case is fundamentally about a package marked delivered but missing."],
              "Urgency Calibration" => [4, "High is reasonable; some agents would call this critical given the Saturday wedding, but high is defensible if SLAs reserve critical for personal-safety issues."],
              "Confidence" => [5, "Right level of commitment for a clear-cut shipping-investigation ticket."] } },
  { input: ticket_inputs[2],
    text: "{ \"category\": \"promo_code\", \"urgency\": \"low\", \"rationale\": \"Pre-purchase question about a promo code rejecting at checkout.\" }",
    scores: { "Category Accuracy" => [5, "Promo_code is the textbook bucket for this."],
              "Urgency Calibration" => [3, "Low is reasonable but medium would also be defensible. The cart is sitting and could lose the conversion. Missed that signal."],
              "Confidence" => [4, "Slight overconfidence on the urgency call given the active cart."] } },
  { input: ticket_inputs[3],
    text: "{ \"category\": \"account_access\", \"secondary\": \"loyalty\", \"urgency\": \"medium\", \"rationale\": \"Customer can't sign in due to SMS 2FA failure; has store credit they want to use before a quoted June 15 date.\" }",
    scores: { "Category Accuracy" => [5, "Account_access is the primary; loyalty as secondary captures the store-credit-expiry concern."],
              "Urgency Calibration" => [5, "Medium is right. They're locked out but have an email-recovery path, and the credit deadline gives a clock without making it critical."],
              "Confidence" => [5, "Well-calibrated. Clear primary, sensible secondary, no over-reach."] } },
  { input: ticket_inputs[4],
    text: "{ \"category\": \"churn_risk\", \"secondary\": \"loyalty\", \"urgency\": \"high\", \"rationale\": \"Long-tenure Gold member evaluating alternatives over loyalty program changes.\" }",
    scores: { "Category Accuracy" => [5, "Churn_risk primary is correct; loyalty secondary captures the trigger. Textbook churn-risk pattern."],
              "Urgency Calibration" => [5, "High is right. 6-year tenure + $4k/year + active alternative-evaluation is exactly when retention should engage fast."],
              "Confidence" => [4, "Slight room to push to critical given the spend, but high is well within range."] } }
]

summary_v1_responses = [
  { input: ticket_inputs[0],
    text: "Refund demand on damaged $749 dryer (order #4827). Customer threatening Friday bank dispute after 11-day no-response.",
    scores: { "Clarity" => [5, "Crisp. Order number, amount, problem, and escalation path all parseable in one read."],
              "Completeness" => [5, "Intent (refund), urgency cue (Friday dispute), routing fact (order #4827, 11-day delay) all present."],
              "Brevity" => [5, "One sentence. Every word earns its place."] } },
  { input: ticket_inputs[1],
    text: "Missing-package report on order #5102 ($315 KitchenAid mixer for Saturday wedding). Tracking shows delivered, customer was home, neighbours' Ring cameras don't show the van.",
    scores: { "Clarity" => [5, "Specific and unambiguous. A shipping investigator can route this without opening the ticket."],
              "Completeness" => [5, "Intent (shipping), urgency cue (Saturday wedding), routing facts (order #, amount, evidence already gathered) all there."],
              "Brevity" => [5, "One sentence, packs everything that matters."] } },
  { input: ticket_inputs[2],
    text: "Pre-purchase question. WELCOME20 promo code rejecting at checkout; cart at $186 waiting on resolution.",
    scores: { "Clarity" => [5, "Plain language, no ambiguity."],
              "Completeness" => [4, "Intent and cart amount are there but the 'within email validity window' detail (which matters for the answer) isn't surfaced."],
              "Brevity" => [5, "One sentence, well-pitched."] } },
  { input: ticket_inputs[3],
    text: "Customer locked out of account: SMS 2FA codes not arriving; phone signal fine. Has $540 store credit they want to use before June 15.",
    scores: { "Clarity" => [5, "Clean and specific. The phone-signal-fine detail tells the agent which troubleshooting branches to skip."],
              "Completeness" => [5, "Intent, troubleshooting context, and the credit deadline (urgency cue) all there."],
              "Brevity" => [4, "Two short sentences. Could compress slightly but the second sentence carries necessary urgency context."] } },
  { input: ticket_inputs[4],
    text: "2019 Gold member (~$X/year spend) considering alternatives over the upcoming Gold program changes. Asking about grandfather pricing for long-tenure members.",
    scores: { "Clarity" => [3, "The placeholder '~$X/year' is a give-away that the model didn't have the spend figure and didn't commit. A triage agent would have to open the ticket to confirm."],
              "Completeness" => [4, "Intent (churn risk) and the trigger (program changes) are there but the placeholder weakens the routing-relevance."],
              "Brevity" => [4, "Two sentences, tight, but the placeholder costs a few words."] } }
]

summary_v2_responses = [
  { input: ticket_inputs[0],
    text: "Refund demand on a damaged dryer, order #4827.",
    scores: { "Clarity" => [4, "Readable, but 'damaged dryer' alone undersells a case that is one step from a bank dispute."],
              "Completeness" => [4, "Intent and order number are there; the Friday bank-dispute deadline (the reason this is urgent) got compressed away."],
              "Brevity" => [5, "As short as it gets. One clean line."] } },
  { input: ticket_inputs[1],
    text: "Missing package on order #5102, customer needs it by Saturday.",
    scores: { "Clarity" => [4, "Clear enough, though 'needs it by Saturday' hides that the deadline is a wedding."],
              "Completeness" => [4, "Intent and the deadline are present; the delivered-but-not-received evidence the customer already gathered is dropped."],
              "Brevity" => [5, "Tight single line."] } },
  { input: ticket_inputs[2],
    text: "WELCOME20 promo code rejecting at checkout.",
    scores: { "Clarity" => [5, "Plain and unambiguous."],
              "Completeness" => [4, "Captures the intent but loses the $186 cart-at-risk signal that makes this worth a fast reply."],
              "Brevity" => [4, "Short, though it reads more like a log line than a summary."] } },
  { input: ticket_inputs[3],
    text: "Customer locked out, SMS 2FA codes not arriving.",
    scores: { "Clarity" => [3, "States the symptom but a reader can't tell whether this is a quick reset or a stuck case."],
              "Completeness" => [4, "Intent is clear; the $540 store credit and its June 15 deadline (both routing-relevant) are gone."],
              "Brevity" => [5, "One short line."] } },
  { input: ticket_inputs[4],
    text: "Gold member unhappy about loyalty program changes.",
    scores: { "Clarity" => [4, "Understandable, but 'unhappy' undersells an active churn risk."],
              "Completeness" => [4, "Misses the tenure and spend that decide whether retention should engage."],
              "Brevity" => [4, "Short, but vague enough that a reader still has to open the ticket."] } }
]

summary_v3_responses = [
  { input: ticket_inputs[0],
    text: "Refund demand on a damaged $749 dryer (order #4827). Customer is threatening a Friday bank dispute after an 11-day no-response.",
    scores: { "Clarity" => [5, "Order number, amount, problem, and the escalation clock all land in one read."],
              "Completeness" => [5, "Intent, the Friday-dispute urgency cue, and the routing facts are all present."],
              "Brevity" => [5, "One sentence carrying everything that matters."] } },
  { input: ticket_inputs[1],
    text: "Missing-package report on order #5102 ($315 KitchenAid mixer, Saturday wedding gift). Tracking shows delivered, customer was home, neighbours' cameras show no delivery van.",
    scores: { "Clarity" => [5, "A shipping investigator can route this without opening the ticket."],
              "Completeness" => [5, "Intent, the wedding deadline, and the delivered-but-missing evidence are all kept."],
              "Brevity" => [5, "One sentence, densely packed, still readable."] } },
  { input: ticket_inputs[2],
    text: "Pre-purchase question. WELCOME20 promo code rejecting at checkout; a $186 cart is waiting on the answer.",
    scores: { "Clarity" => [5, "Plain language, no ambiguity."],
              "Completeness" => [5, "Intent plus the at-risk cart value that tells triage this is time-sensitive."],
              "Brevity" => [5, "One tight sentence."] } },
  { input: ticket_inputs[3],
    text: "Customer locked out of their account: SMS 2FA codes not arriving despite good signal. Has $540 in store credit they want to use before June 15.",
    scores: { "Clarity" => [5, "The good-signal detail tells the agent which troubleshooting branches to skip."],
              "Completeness" => [5, "Intent, troubleshooting context, and the credit deadline all present."],
              "Brevity" => [4, "Two short sentences; the second carries the necessary urgency context."] } },
  { input: ticket_inputs[4],
    text: "2019 Gold member spending ~$4k/year is weighing alternatives after the loyalty program changes; asking whether grandfather pricing exists for long-tenure members.",
    scores: { "Clarity" => [4, "Clear, with the tenure and spend a retention agent needs to act."],
              "Completeness" => [4, "Intent, trigger, and the spend figure are all there."],
              "Brevity" => [5, "Two sentences, no wasted words."] } }
]

seed_run = lambda do |name:, prompt:, dataset:, metrics:, days_ago:, responses:, tags:|
  at = days_ago.days.ago
  run = CompletionKit::Run.find_or_create_by!(name: name) do |r|
    r.prompt = prompt
    r.dataset = dataset
    r.judge_model = "gpt-4.1-mini"
    r.status = "completed"
    r.progress_current = responses.size
    r.progress_total = responses.size
    r.created_at = at
    r.updated_at = at
  end

  metrics.each_with_index do |metric, i|
    CompletionKit::RunMetric.find_or_create_by!(run: run, metric: metric) { |rm| rm.position = i + 1 }
  end

  responses.each do |rd|
    response = run.responses.find_or_create_by!(input_data: rd[:input]) do |r|
      r.response_text = rd[:text]
      r.status = "succeeded"
      r.created_at = at
      r.updated_at = at
    end

    rd[:scores].each do |metric_name, (score, feedback)|
      metric = CompletionKit::Metric.find_by!(name: metric_name)
      response.reviews.find_or_create_by!(metric: metric) do |review|
        review.metric_name = metric_name
        review.instruction = metric.instruction
        review.status = "succeeded"
        review.ai_score = score
        review.ai_feedback = feedback
        review.created_at = at
        review.updated_at = at
      end
    end
  end

  run.update!(tag_names: tags) if tags.present? && run.tags.empty?
  run
end

runs = [
  { name: "Support Reply Generator v1 #1", prompt: reply_prompt,  dataset: dataset, metrics: reply_metrics,   days_ago: 13, responses: reply_responses,     tags: %w[customer-support reply] },
  { name: "Ticket Triage v1 #1",           prompt: triage_prompt, dataset: dataset, metrics: triage_metrics,  days_ago: 13, responses: triage_responses,    tags: %w[customer-support triage] },
  { name: "Ticket Summary v1 #1",          prompt: summary_v1,    dataset: dataset, metrics: summary_metrics, days_ago: 11, responses: summary_v1_responses, tags: %w[customer-support summary] },
  { name: "Ticket Summary v1 #2",          prompt: summary_v1,    dataset: dataset, metrics: summary_metrics, days_ago: 11, responses: summary_v1_responses, tags: %w[customer-support summary] },
  { name: "Ticket Summary v2 #1",          prompt: summary_v2,    dataset: dataset, metrics: summary_metrics, days_ago: 6,  responses: summary_v2_responses, tags: %w[customer-support summary] },
  { name: "Support Reply Generator v1 #2", prompt: reply_prompt,  dataset: dataset, metrics: reply_metrics,   days_ago: 4,  responses: reply_responses,     tags: %w[customer-support reply] },
  { name: "Ticket Triage v1 #2",           prompt: triage_prompt, dataset: dataset, metrics: triage_metrics,  days_ago: 4,  responses: triage_responses,    tags: %w[customer-support triage] },
  { name: "Ticket Summary v3 #1",          prompt: summary_v3,    dataset: dataset, metrics: summary_metrics, days_ago: 2,  responses: summary_v3_responses, tags: %w[customer-support summary] },
  { name: "Ticket Triage v1 #3",           prompt: triage_prompt, dataset: dataset, metrics: triage_metrics,  days_ago: 1,  responses: triage_responses,    tags: %w[customer-support triage] }
]

runs.each { |attrs| seed_run.call(**attrs) }

%w[customer-support reply triage summary].each do |tag_name|
  CompletionKit::Tag.find_or_create_by!(name: tag_name)
end

CompletionKit::Dataset.find_by(name: "Customer Tickets (sample)")&.update!(tag_names: ["customer-support"])

prompt_tags = {
  "Support Reply Generator" => ["customer-support", "reply"],
  "Ticket Triage"           => ["customer-support", "triage"],
  "Ticket Summary"          => ["customer-support", "summary"]
}
prompt_tags.each do |prompt_name, names|
  CompletionKit::Prompt.where(name: prompt_name).each { |p| p.update!(tag_names: names) }
end

metric_tags = {
  "Tone"                => ["reply"],
  "Helpfulness"         => ["reply"],
  "Accuracy"            => ["reply"],
  "Category Accuracy"   => ["triage"],
  "Urgency Calibration" => ["triage"],
  "Confidence"          => ["triage"],
  "Clarity"             => ["summary"],
  "Completeness"        => ["summary"],
  "Brevity"             => ["summary"]
}
metric_tags.each do |metric_name, names|
  CompletionKit::Metric.find_by(name: metric_name)&.update!(tag_names: names)
end

seed_calibrations = lambda do |metric_name:, agree:, disagree:, borderline:|
  metric = CompletionKit::Metric.find_by!(name: metric_name)
  jv = CompletionKit::JudgeVersion.ensure_current_for(metric)
  reviewed_responses = CompletionKit::Response.joins(:reviews)
    .where(reviews: { metric_id: metric.id })
    .where.not(reviews: { ai_score: nil })
    .distinct.to_a
  next if reviewed_responses.empty?

  total = agree + disagree + borderline
  total.times do |i|
    resp = reviewed_responses[i % reviewed_responses.size]
    operator = "operator_#{(i / reviewed_responses.size) + 1}"
    verdict = if i < agree
                "agree"
              elsif i < agree + disagree
                "disagree"
              else
                "borderline"
              end

    next if CompletionKit::Calibration.exists?(response_id: resp.id, metric_id: metric.id, created_by: operator)

    attrs = { run: resp.run, response: resp, metric: metric, judge_version: jv, verdict: verdict, created_by: operator }
    if verdict == "disagree"
      live = resp.reviews.find_by(metric_id: metric.id)
      attrs[:corrected_score] = ((live&.ai_score || 3.0) - 1).clamp(1, 5)
      attrs[:note] = "Judge was a star too generous here."
    elsif verdict == "borderline"
      attrs[:note] = "Rubric was ambiguous between two bands."
    end
    CompletionKit::Calibration.create!(attrs)
  end
end

seed_calibrations.call(metric_name: "Tone",                agree: 3,  disagree: 1,  borderline: 0)
seed_calibrations.call(metric_name: "Accuracy",            agree: 11, disagree: 3,  borderline: 4)
seed_calibrations.call(metric_name: "Confidence",          agree: 28, disagree: 3,  borderline: 1)
seed_calibrations.call(metric_name: "Urgency Calibration", agree: 5,  disagree: 2,  borderline: 5)

accuracy_metric = CompletionKit::Metric.find_by!(name: "Accuracy")
pinned = CompletionKit::Calibration.where(metric_id: accuracy_metric.id, verdict: "disagree").first
if pinned && Array(accuracy_metric.few_shot_examples).none? { |fs| fs["calibration_id"] == pinned.id }
  resp = pinned.response
  review = resp.reviews.find_by(metric_id: accuracy_metric.id)
  examples = Array(accuracy_metric.few_shot_examples)
  examples << {
    "input" => resp.input_data.to_s.truncate(2000),
    "response" => resp.response_text.to_s.truncate(2000),
    "judge_score" => review&.ai_score&.to_f,
    "judge_feedback" => review&.ai_feedback.to_s.truncate(1000),
    "human_score" => pinned.corrected_score&.to_f,
    "human_note" => pinned.note.to_s.truncate(1000),
    "calibration_id" => pinned.id,
    "added_at" => Time.current.utc.iso8601
  }
  accuracy_metric.update!(few_shot_examples: examples)
end

if CompletionKit::JudgeVersion.drafts.where(metric_id: accuracy_metric.id, source: "suggestion").none?
  CompletionKit::JudgeVersion.create!(
    metric: accuracy_metric,
    instruction: "Are the factual claims and policy statements in the reply correct, and grounded in the ticket plus known company facts? Flag any invented policy, price, deadline, or product feature. Soft claims that could mislead also count against the score.",
    rubric_bands: [
      { "stars" => 5, "description" => "Every factual claim is verifiable and explicitly grounded in the ticket. Policies and numbers cited are real and exact." },
      { "stars" => 4, "description" => "One minor embellishment or slightly soft claim, but nothing that would mislead the customer." },
      { "stars" => 3, "description" => "Mostly accurate but includes one detail that's questionable (e.g. cites a feature with the wrong limit, references a policy loosely)." },
      { "stars" => 2, "description" => "Multiple inaccuracies or invented details that could cause material confusion or future complaints." },
      { "stars" => 1, "description" => "Contradicts ticket facts, invents policies that don't exist, or commits the company to something it can't deliver." }
    ],
    state: "draft",
    source: "suggestion",
    current: false
  )
end

helpfulness_metric = CompletionKit::Metric.find_by!(name: "Helpfulness")
if CompletionKit::JudgeVersion.drafts.where(metric_id: helpfulness_metric.id, source: "edit").none?
  CompletionKit::JudgeVersion.create!(
    metric: helpfulness_metric,
    instruction: "Does the reply move the case forward in one round-trip? It should resolve the question, propose a concrete next step the customer can act on, or both. Replies that defer, ask for information already in the ticket, or commit to nothing don't count as helpful.",
    rubric_bands: helpfulness_metric.rubric_bands,
    state: "draft",
    source: "edit",
    current: false
  )
end

puts "Seeded: #{CompletionKit::Model.count} models, #{CompletionKit::Prompt.count} prompts, #{CompletionKit::Dataset.count} datasets, #{CompletionKit::Metric.count} metrics, #{CompletionKit::Run.count} runs, #{CompletionKit::Response.count} responses, #{CompletionKit::Review.count} reviews, #{CompletionKit::Tag.count} tags, #{CompletionKit::Calibration.count} calibrations, #{CompletionKit::JudgeVersion.drafts.count} draft judge versions"

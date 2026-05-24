module CompletionKit
  module Onboarding
    # Opt-in starter data for the onboarding page: one dataset + one prompt so a
    # brand-new install has something to poke at. Idempotent. A no-op once the
    # workspace already has any prompt or dataset. Deliberately does NOT create a
    # provider credential (needs a real API key) or a run (user-initiated).
    module SampleData
      SAMPLE_CSV = <<~CSV.freeze
        ticket
        "My order #4827 arrived with a dented panel. I emailed photos 11 days ago and heard nothing. Today I was told the return window 'closed'. I paid $749. I want a refund or replacement, not store credit."
        "Tracking says delivered to my porch Tuesday 3:47pm. I was home all day, nothing arrived, neighbours' cameras show no van. Order #5102. A $315 mixer, wedding gift, wedding is Saturday. Can someone look today?"
        "WELCOME20 says 'invalid' at checkout but the promo email says it's good through May 31. Same email I'm signed in with. Tried Chrome and Safari. Cart is $186 waiting on you."
      CSV

      SAMPLE_PROMPT = {
        name: "Sample: Support reply",
        description: "A starter prompt. Drafts a warm, professional reply to a customer support ticket. Edit it or delete it; it's just here to get you going.",
        template: "You are a senior customer-support specialist. Write a warm, professional reply to this ticket. Acknowledge the customer's situation, be specific about next steps, and don't be defensive.\n\nTicket:\n{{ticket}}",
        llm_model: "gpt-4o-mini"
      }.freeze

      module_function

      def install!
        return if CompletionKit::Prompt.exists? || CompletionKit::Dataset.exists?

        CompletionKit::Dataset.create!(name: "Sample: Customer tickets", csv_data: SAMPLE_CSV)
        CompletionKit::Prompt.create!(
          name: SAMPLE_PROMPT[:name],
          description: SAMPLE_PROMPT[:description],
          template: SAMPLE_PROMPT[:template],
          llm_model: SAMPLE_PROMPT[:llm_model]
        )
      end
    end
  end
end

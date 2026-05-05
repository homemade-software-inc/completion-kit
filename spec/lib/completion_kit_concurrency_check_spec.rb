require "rails_helper"

RSpec.describe CompletionKit::ConcurrencyCheck do
  let(:logger) { instance_double(Logger, warn: nil) }

  describe ".warn_if_misconfigured" do
    context "when threads < llm_cap" do
      it "logs a warning" do
        allow(ENV).to receive(:fetch).with("SOLID_QUEUE_THREADS", 10).and_return(2)
        allow(ENV).to receive(:fetch).with("COMPLETION_KIT_LLM_CONCURRENCY", 10).and_return(10)

        described_class.warn_if_misconfigured(logger)

        expect(logger).to have_received(:warn).with(
          /SOLID_QUEUE_THREADS=2 is less than COMPLETION_KIT_LLM_CONCURRENCY=10/
        )
      end
    end

    context "when threads >= llm_cap" do
      it "does not log a warning" do
        allow(ENV).to receive(:fetch).with("SOLID_QUEUE_THREADS", 10).and_return(10)
        allow(ENV).to receive(:fetch).with("COMPLETION_KIT_LLM_CONCURRENCY", 10).and_return(10)

        described_class.warn_if_misconfigured(logger)

        expect(logger).not_to have_received(:warn)
      end
    end
  end
end

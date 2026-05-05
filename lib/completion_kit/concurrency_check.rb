module CompletionKit
  module ConcurrencyCheck
    def self.warn_if_misconfigured(logger)
      threads = ENV.fetch("SOLID_QUEUE_THREADS", 10).to_i
      llm_cap = ENV.fetch("COMPLETION_KIT_LLM_CONCURRENCY", 10).to_i

      if threads < llm_cap
        logger.warn(
          "[CompletionKit] SOLID_QUEUE_THREADS=#{threads} is less than " \
          "COMPLETION_KIT_LLM_CONCURRENCY=#{llm_cap}; threads will be the " \
          "actual bottleneck and the per-provider cap will never be reached."
        )
      end
    end
  end
end

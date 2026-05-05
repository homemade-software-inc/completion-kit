Rails.application.config.after_initialize do
  CompletionKit::ConcurrencyCheck.warn_if_misconfigured(Rails.logger)
end

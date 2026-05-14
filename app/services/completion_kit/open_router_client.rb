module CompletionKit
  class OpenRouterClient < LlmClient
    BASE_URL = "https://openrouter.ai".freeze
    REFERER = "https://completionkit.com".freeze
    APP_TITLE = "CompletionKit".freeze

    def temperature_dropped?
      @temperature_dropped == true
    end

    def generate_completion(prompt, options = {})
      @temperature_dropped = false
      return "Error: API key not configured" unless configured?

      model = options[:model] || "openai/gpt-4o-mini"
      max_tokens = options[:max_tokens] || 8192
      temperature = options[:temperature] || 0.7

      response = post_chat(model: model, prompt: prompt, max_tokens: max_tokens, temperature: temperature)

      if response.status == 400 && temperature_unsupported?(response.body)
        @temperature_dropped = true
        response = post_chat(model: model, prompt: prompt, max_tokens: max_tokens, temperature: nil)
      end

      if response.status == 429
        raise CompletionKit::RateLimitError.new(
          response.body.to_s.truncate(500),
          provider: "openrouter",
          status: 429,
          retry_after: response.headers && response.headers["Retry-After"]&.to_i
        )
      end

      if response.success?
        data = JSON.parse(response.body)
        choice = data.dig("choices", 0) || {}
        if choice["finish_reason"] == "length"
          return "Error: response truncated by max_tokens=#{max_tokens} before visible content was emitted (reasoning model burned through the budget)"
        end
        content = choice.dig("message", "content").to_s.strip
        return "Error: model returned empty content" if content.empty?
        content
      else
        "Error: #{response.status} - #{response.body}"
      end
    rescue CompletionKit::RateLimitError
      raise
    rescue Faraday::Error
      raise
    rescue => e
      "Error: #{e.message}"
    end

    def available_models
      []
    end

    def configured?
      api_key.present?
    end

    def configuration_errors
      errors = []
      errors << "OpenRouter API key is not configured" unless api_key.present?
      errors
    end

    private

    def api_key
      @config[:api_key] || ENV["OPENROUTER_API_KEY"]
    end

    def post_chat(model:, prompt:, max_tokens:, temperature:)
      body = {
        model: model,
        messages: [{ role: "user", content: prompt }],
        max_tokens: max_tokens
      }
      body[:temperature] = temperature unless temperature.nil?

      build_connection(BASE_URL, timeout: 30, open_timeout: 5).post do |req|
        req.url "/api/v1/chat/completions"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{api_key}"
        req.headers["HTTP-Referer"] = REFERER
        req.headers["X-Title"] = APP_TITLE
        req.body = body.to_json
      end
    end

    def temperature_unsupported?(body)
      s = body.to_s
      s.include?("temperature") && (s.include?("deprecated") || s.include?("not supported") || s.include?("Unsupported parameter"))
    end
  end
end

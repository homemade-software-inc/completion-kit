module CompletionKit
  class OpenRouterClient < LlmClient
    BASE_URL = "https://openrouter.ai/api/v1".freeze
    REFERER = "https://completionkit.com".freeze
    APP_TITLE = "CompletionKit".freeze

    def generate_completion(prompt, options = {})
      return "Error: API key not configured" unless configured?

      model = options[:model] || "openai/gpt-4o-mini"
      max_tokens = options[:max_tokens] || 1000
      temperature = options[:temperature] || 0.7

      response = build_connection(BASE_URL, timeout: 30, open_timeout: 5).post do |req|
        req.url "/chat/completions"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{api_key}"
        req.headers["HTTP-Referer"] = REFERER
        req.headers["X-Title"] = APP_TITLE
        req.body = {
          model: model,
          messages: [{ role: "user", content: prompt }],
          max_tokens: max_tokens,
          temperature: temperature
        }.to_json
      end

      if response.success?
        data = JSON.parse(response.body)
        data.dig("choices", 0, "message", "content").to_s.strip
      else
        "Error: #{response.status} - #{response.body}"
      end
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
  end
end

module CompletionKit
  class OpenAiClient < LlmClient
    STATIC_MODELS = [
      { id: "gpt-5.4-mini", name: "GPT-5.4 Mini" },
      { id: "gpt-4.1-mini", name: "GPT-4.1 Mini" },
      { id: "gpt-4o-mini", name: "GPT-4o Mini" }
    ].freeze

    def temperature_dropped?
      @temperature_dropped == true
    end

    def generate_completion(prompt, options = {})
      @temperature_dropped = false
      return "Error: API key not configured" unless configured?

      model = options[:model] || "gpt-4.1-mini"
      max_tokens = options[:max_tokens] || 1000
      temperature = options[:temperature] || 0.7

      response = post_responses(model: model, prompt: prompt, max_tokens: max_tokens, temperature: temperature)

      if response.status == 400 && temperature_unsupported?(response.body)
        @temperature_dropped = true
        response = post_responses(model: model, prompt: prompt, max_tokens: max_tokens, temperature: nil)
      end

      if response.status == 429
        raise CompletionKit::RateLimitError.new(
          response.body.to_s.truncate(500),
          provider: "openai",
          status: 429,
          retry_after: response.headers && response.headers["Retry-After"]&.to_i
        )
      end

      if response.success?
        data = JSON.parse(response.body)
        message = Array(data["output"]).find { |o| o["type"] == "message" }
        message&.dig("content", 0, "text").to_s.strip
      else
        "Error: #{response.status} - #{response.body}"
      end
    rescue CompletionKit::RateLimitError
      raise
    rescue Faraday::Error => e
      raise
    rescue => e
      "Error: #{e.message}"
    end

    def available_models
      STATIC_MODELS
    end

    def configured?
      api_key.present?
    end

    def configuration_errors
      errors = []
      errors << "OpenAI API key is not configured" unless api_key.present?
      errors
    end

    private

    def api_key
      @config[:api_key] || ENV["OPENAI_API_KEY"]
    end

    def post_responses(model:, prompt:, max_tokens:, temperature:)
      body = {
        model: model,
        input: prompt,
        instructions: "You are a helpful assistant.",
        max_output_tokens: max_tokens,
        store: false
      }
      body[:temperature] = temperature unless temperature.nil?

      build_connection("https://api.openai.com").post do |req|
        req.url "/v1/responses"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{api_key}"
        req.body = body.to_json
      end
    end

    def temperature_unsupported?(body)
      s = body.to_s
      s.include?("temperature") && (s.include?("deprecated") || s.include?("not supported") || s.include?("Unsupported parameter"))
    end
  end
end

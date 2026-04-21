module CompletionKit
  class AnthropicClient < LlmClient
    STATIC_MODELS = [
      { id: "claude-3-7-sonnet-latest", name: "Claude 3.7 Sonnet" },
      { id: "claude-3-5-haiku-latest", name: "Claude 3.5 Haiku" }
    ].freeze

    def generate_completion(prompt, options = {})
      return "Error: API key not configured" unless configured?

      model = options[:model] || "claude-3-7-sonnet-latest"
      max_tokens = options[:max_tokens] || 1000
      temperature = options[:temperature] || 0.7

      response = build_connection("https://api.anthropic.com").post do |req|
        req.url "/v1/messages"
        req.headers["Content-Type"] = "application/json"
        req.headers["x-api-key"] = api_key
        req.headers["anthropic-version"] = "2023-06-01"
        req.body = {
          model: model,
          messages: [
            { role: "user", content: prompt }
          ],
          max_tokens: max_tokens,
          temperature: temperature
        }.to_json
      end
      
      if response.success?
        data = JSON.parse(response.body)
        data["content"][0]["text"].strip
      else
        "Error: #{response.status} - #{response.body}"
      end
    rescue => e
      "Error: #{e.message}"
    end

    def available_models
      return STATIC_MODELS unless configured?

      response = build_connection("https://api.anthropic.com").get("/v1/models?limit=100") do |req|
        req.headers["x-api-key"] = api_key
        req.headers["anthropic-version"] = "2023-06-01"
      end

      return STATIC_MODELS unless response.success?

      entries = JSON.parse(response.body).fetch("data", [])
      models = entries.map { |entry| { id: entry["id"], name: entry["display_name"] || entry["id"] } }
      models.presence || STATIC_MODELS
    rescue StandardError
      STATIC_MODELS
    end

    def configured?
      api_key.present?
    end

    def configuration_errors
      errors = []
      errors << "Anthropic API key is not configured" unless api_key.present?
      errors
    end

    private

    def api_key
      @config[:api_key] || ENV["ANTHROPIC_API_KEY"]
    end
  end
end

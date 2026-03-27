module CompletionKit
  class AnthropicClient < LlmClient
    STATIC_MODELS = [
      { id: "claude-3-7-sonnet-latest", name: "Claude 3.7 Sonnet" },
      { id: "claude-3-5-haiku-latest", name: "Claude 3.5 Haiku" }
    ].freeze

    def generate_completion(prompt, options = {})
      return "Error: API key not configured" unless configured?
      
      require "faraday"
      require "faraday/retry"
      require "json"
      
      model = options[:model] || "claude-3-7-sonnet-latest"
      max_tokens = options[:max_tokens] || 1000
      temperature = options[:temperature] || 0.7
      
      conn = Faraday.new(url: "https://api.anthropic.com") do |f|
        f.request :retry, max: 2, interval: 0.5
        f.adapter Faraday.default_adapter
      end
      
      response = conn.post do |req|
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

      require "faraday"
      require "faraday/retry"
      require "json"

      response = Faraday.get("https://api.anthropic.com/v1/models") do |req|
        req.headers["x-api-key"] = api_key
        req.headers["anthropic-version"] = "2023-06-01"
      end

      return STATIC_MODELS unless response.success?

      models = JSON.parse(response.body).fetch("data", []).map { |entry| entry["id"] }.grep(/\Aclaude-/).sort
      models.map { |id| { id: id, name: id } }.presence || STATIC_MODELS
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

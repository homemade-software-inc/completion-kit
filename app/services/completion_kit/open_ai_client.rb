module CompletionKit
  class OpenAiClient < LlmClient
    STATIC_MODELS = [
      { id: "gpt-5.4-mini", name: "GPT-5.4 Mini" },
      { id: "gpt-4.1-mini", name: "GPT-4.1 Mini" },
      { id: "gpt-4o-mini", name: "GPT-4o Mini" }
    ].freeze

    def generate_completion(prompt, options = {})
      return "Error: API key not configured" unless configured?

      require "faraday"
      require "faraday/retry"
      require "json"

      model = options[:model] || "gpt-4.1-mini"
      max_tokens = options[:max_tokens] || 1000
      temperature = options[:temperature] || 0.7

      conn = Faraday.new(url: "https://api.openai.com") do |f|
        f.request :retry, max: 2, interval: 0.5
        f.adapter Faraday.default_adapter
      end

      response = conn.post do |req|
        req.url "/v1/responses"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{api_key}"
        req.body = {
          model: model,
          input: prompt,
          instructions: "You are a helpful assistant.",
          max_output_tokens: max_tokens,
          temperature: temperature,
          store: false
        }.to_json
      end

      if response.success?
        data = JSON.parse(response.body)
        data["output"][0]["content"][0]["text"].strip
      else
        "Error: #{response.status} - #{response.body}"
      end
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
  end
end

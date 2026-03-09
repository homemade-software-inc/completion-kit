module CompletionKit
  class OpenAiClient < LlmClient
    STATIC_MODELS = [
      { id: "gpt-4.1", name: "GPT-4.1" },
      { id: "gpt-4o", name: "GPT-4o" },
      { id: "gpt-4o-mini", name: "GPT-4o mini" }
    ].freeze

    def generate_completion(prompt, options = {})
      return "Error: API key not configured" unless configured?
      
      require "faraday"
      require "json"
      
      model = options[:model] || "gpt-4.1"
      max_tokens = options[:max_tokens] || 1000
      temperature = options[:temperature] || 0.7
      
      conn = Faraday.new(url: "https://api.openai.com") do |f|
        f.request :retry, max: 2, interval: 0.5
        f.adapter Faraday.default_adapter
      end
      
      response = conn.post do |req|
        req.url "/v1/chat/completions"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{api_key}"
        req.body = {
          model: model,
          messages: [
            { role: "system", content: "You are a helpful assistant." },
            { role: "user", content: prompt }
          ],
          max_tokens: max_tokens,
          temperature: temperature
        }.to_json
      end
      
      if response.success?
        data = JSON.parse(response.body)
        data["choices"][0]["message"]["content"].strip
      else
        "Error: #{response.status} - #{response.body}"
      end
    rescue => e
      "Error: #{e.message}"
    end

    def available_models
      return STATIC_MODELS unless configured?

      require "faraday"
      require "json"

      response = Faraday.get("https://api.openai.com/v1/models") do |req|
        req.headers["Authorization"] = "Bearer #{api_key}"
      end

      return STATIC_MODELS unless response.success?

      models = JSON.parse(response.body).fetch("data", []).map { |entry| entry["id"] }.grep(/\Agpt-/).sort
      models.map { |id| { id: id, name: id } }.presence || STATIC_MODELS
    rescue StandardError
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

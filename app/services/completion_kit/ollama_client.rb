module CompletionKit
  class OllamaClient < LlmClient
    def generate_completion(prompt, options = {})
      return "Error: API endpoint not configured" unless configured?

      model = options[:model]
      max_tokens = options[:max_tokens] || 1000
      temperature = options[:temperature] || 0.7

      response = build_connection(api_endpoint).post do |req|
        req.url "/v1/completions"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{api_key}" if api_key.present?
        req.body = {
          model: model,
          prompt: prompt,
          max_tokens: max_tokens,
          temperature: temperature
        }.to_json
      end

      if response.success?
        data = JSON.parse(response.body)
        data["choices"][0]["text"].strip
      else
        "Error: #{response.status} - #{response.body}"
      end
    rescue => e
      "Error: #{e.message}"
    end

    def available_models
      return [] unless configured?

      response = build_connection(api_endpoint).get("/v1/models") do |req|
        req.headers["Authorization"] = "Bearer #{api_key}" if api_key.present?
      end

      return [] unless response.success?

      models = JSON.parse(response.body).fetch("data", []).map { |entry| entry["id"] }.sort
      models.map { |id| { id: id, name: id } }
    rescue StandardError
      []
    end

    def configured?
      api_endpoint.present?
    end

    def configuration_errors
      errors = []
      errors << "Ollama API endpoint is not configured" unless api_endpoint.present?
      errors
    end

    private

    def api_key
      @config[:api_key] || ENV["OLLAMA_API_KEY"]
    end

    def api_endpoint
      (@config[:api_endpoint] || ENV["OLLAMA_API_ENDPOINT"] || "http://localhost:11434/v1").to_s.delete_suffix("/")
    end
  end
end

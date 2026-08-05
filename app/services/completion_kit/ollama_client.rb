module CompletionKit
  class OllamaClient < LlmClient

    def generate_completion(prompt, options = {})
      @temperature_dropped = false
      return "Error: API endpoint not configured" unless configured?
      return "Error: API endpoint resolves to a private address" unless ProviderEndpoint.safe?(api_endpoint)

      model = options[:model]
      max_tokens = options[:max_tokens] || 1000
      temperature = resolve_temperature(options)

      response = post_completion(model: model, prompt: prompt, max_tokens: max_tokens, temperature: temperature)

      if response.status == 400 && !temperature.nil? && temperature_unsupported?(response.body)
        @temperature_dropped = true
        response = post_completion(model: model, prompt: prompt, max_tokens: max_tokens, temperature: nil)
      end

      if response.status == 429
        raise CompletionKit::RateLimitError.new(
          response.body.to_s.truncate(500),
          provider: "ollama",
          status: 429,
          retry_after: nil
        )
      end

      if response.success?
        data = JSON.parse(response.body)
        data["choices"][0]["text"].strip
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
      return [] unless configured?
      return [] unless ProviderEndpoint.safe?(api_endpoint)

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
      raw = @config[:api_endpoint] || ENV["OLLAMA_API_ENDPOINT"]
      raw ||= "http://localhost:11434/v1" if CompletionKit.config.allow_loopback_endpoints
      raw.to_s.delete_suffix("/")
    end

    def post_completion(model:, prompt:, max_tokens:, temperature:)
      body = {
        model: model,
        prompt: prompt,
        max_tokens: max_tokens
      }
      body[:temperature] = temperature unless temperature.nil?

      build_connection(api_endpoint).post do |req|
        req.url "/v1/completions"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{api_key}" if api_key.present?
        req.body = body.to_json
      end
    end

  end
end

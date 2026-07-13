module CompletionKit
  class AzureFoundryClient < LlmClient
    def temperature_dropped?
      @temperature_dropped == true
    end

    def generate_completion(prompt, options = {})
      @temperature_dropped = false
      return "Error: Azure provider is not fully configured" unless configured?
      return "Error: API endpoint resolves to a private address" unless ProviderEndpoint.safe?(api_endpoint)

      model = options[:model]
      max_tokens = options[:max_tokens] || 1000
      temperature = options[:temperature] || 0.7

      response = post_chat(model: model, prompt: prompt, max_tokens: max_tokens, temperature: temperature)

      if response.status == 400 && temperature_unsupported?(response.body)
        @temperature_dropped = true
        response = post_chat(model: model, prompt: prompt, max_tokens: max_tokens, temperature: nil)
      end

      if response.status == 429
        raise CompletionKit::RateLimitError.new(
          response.body.to_s.truncate(500),
          provider: "azure_foundry",
          status: 429,
          retry_after: response.headers["Retry-After"]&.to_i
        )
      end

      if response.success?
        data = JSON.parse(response.body)
        content = data.dig("choices", 0, "message", "content").to_s.strip
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
      return [] unless configured?
      return [] unless ProviderEndpoint.safe?(api_endpoint)

      response = build_connection(azure_base_url).get(models_path) do |req|
        req.headers["api-key"] = api_key
      end
      return [] unless response.success?

      JSON.parse(response.body).fetch("data", []).map { |entry| { id: entry["id"], name: entry["id"] } }
    rescue StandardError
      []
    end

    def configured?
      configuration_errors.empty?
    end

    def configuration_errors
      errors = []
      errors << "Azure endpoint is not configured" if api_endpoint.blank?
      errors << "Azure API key is not configured" if api_key.blank?
      errors
    end

    private

    def api_key
      @config[:api_key]
    end

    def api_endpoint
      @config[:api_endpoint]
    end

    def api_version
      @config[:api_version]
    end

    def azure_base_url
      api_endpoint.to_s.strip.delete_suffix("/")
    end

    def v1_mode?
      api_version.blank?
    end

    def models_path
      v1_mode? ? "/openai/v1/models" : "/openai/deployments?api-version=#{api_version}"
    end

    def post_chat(model:, prompt:, max_tokens:, temperature:)
      body = { messages: [{ role: "user", content: prompt }], max_tokens: max_tokens }
      body[:model] = model if v1_mode?
      body[:temperature] = temperature unless temperature.nil?

      build_connection(azure_base_url, timeout: 30, open_timeout: 5).post do |req|
        req.url(v1_mode? ? "/openai/v1/chat/completions" : "/openai/deployments/#{model}/chat/completions?api-version=#{api_version}")
        req.headers["Content-Type"] = "application/json"
        req.headers["api-key"] = api_key
        req.body = body.to_json
      end
    end

    def temperature_unsupported?(body)
      s = body.to_s
      s.include?("temperature") && (s.include?("deprecated") || s.include?("not supported") || s.include?("Unsupported parameter"))
    end
  end
end

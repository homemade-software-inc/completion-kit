module CompletionKit
  class LlamaClient < LlmClient
    STATIC_MODELS = [
      { id: "llama-3.1-8b-instruct", name: "Llama 3.1 8B Instruct" },
      { id: "llama-3.1-70b-instruct", name: "Llama 3.1 70B Instruct" }
    ].freeze

    def generate_completion(prompt, options = {})
      return "Error: API credentials not configured" unless configured?
      
      require "faraday"
      require "faraday/retry"
      require "json"
      
      model = options[:model] || STATIC_MODELS.first[:id]
      max_tokens = options[:max_tokens] || 1000
      temperature = options[:temperature] || 0.7
      
      conn = Faraday.new(url: api_endpoint) do |f|
        f.request :retry, max: 2, interval: 0.5
        f.adapter Faraday.default_adapter
      end
      
      response = conn.post do |req|
        req.url "/v1/completions"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{api_key}"
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
      return STATIC_MODELS unless configured?

      require "faraday"
      require "faraday/retry"
      require "json"

      response = Faraday.get("#{api_endpoint}/v1/models") do |req|
        req.headers["Authorization"] = "Bearer #{api_key}" if api_key.present?
      end

      return STATIC_MODELS unless response.success?

      models = JSON.parse(response.body).fetch("data", []).map { |entry| entry["id"] }.sort
      models.map { |id| { id: id, name: id } }.presence || STATIC_MODELS
    rescue StandardError
      STATIC_MODELS
    end

    def configured?
      api_key.present? && api_endpoint.present?
    end

    def configuration_errors
      errors = []
      errors << "Llama API key is not configured" unless api_key.present?
      errors << "Llama API endpoint is not configured" unless api_endpoint.present?
      errors
    end

    private

    def api_key
      @config[:api_key] || ENV["LLAMA_API_KEY"]
    end
    
    def api_endpoint
      (@config[:api_endpoint] || ENV["LLAMA_API_ENDPOINT"] || "https://api.llama.ai").to_s.delete_suffix("/")
    end
  end
end

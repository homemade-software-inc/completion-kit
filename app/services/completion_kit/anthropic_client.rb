module CompletionKit
  class AnthropicClient < LlmClient
    # Anthropic API client for Claude models
    
    # Generate a completion for the given prompt
    # @param prompt [String] The prompt to generate a completion for
    # @param options [Hash] Additional options for the completion
    # @return [String] The generated completion
    def generate_completion(prompt, options = {})
      return "API key not configured" unless configured?
      
      require 'faraday'
      require 'json'
      
      model = options[:model] || 'claude-3-sonnet'
      max_tokens = options[:max_tokens] || 1000
      temperature = options[:temperature] || 0.7
      
      conn = Faraday.new(url: 'https://api.anthropic.com') do |f|
        f.request :retry, max: 2, interval: 0.5
        f.adapter Faraday.default_adapter
      end
      
      response = conn.post do |req|
        req.url '/v1/messages'
        req.headers['Content-Type'] = 'application/json'
        req.headers['x-api-key'] = api_key
        req.headers['anthropic-version'] = '2023-06-01'
        req.body = {
          model: model,
          messages: [
            { role: 'user', content: prompt }
          ],
          max_tokens: max_tokens,
          temperature: temperature
        }.to_json
      end
      
      if response.success?
        data = JSON.parse(response.body)
        data['content'][0]['text'].strip
      else
        "Error: #{response.status} - #{response.body}"
      end
    rescue => e
      "Error: #{e.message}"
    end
    
    # Get the available models for this client
    # @return [Array<Hash>] Array of model information hashes
    def available_models
      [
        { id: 'claude-3-opus', name: 'Claude 3 Opus' },
        { id: 'claude-3-sonnet', name: 'Claude 3 Sonnet' }
      ]
    end
    
    # Check if the client is properly configured
    # @return [Boolean] True if configured, false otherwise
    def configured?
      api_key.present?
    end
    
    # Get configuration errors if any
    # @return [Array<String>] Array of error messages
    def configuration_errors
      errors = []
      errors << "Anthropic API key is not configured" unless api_key.present?
      errors
    end
    
    private
    
    def api_key
      @config[:api_key] || ENV['ANTHROPIC_API_KEY']
    end
  end
end

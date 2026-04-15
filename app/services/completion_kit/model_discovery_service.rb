require "faraday"
require "faraday/retry"
require "json"

module CompletionKit
  class ModelDiscoveryService
    def initialize(config:)
      @provider = config[:provider]
      @api_key = config[:api_key]
      @api_endpoint = config[:api_endpoint]
    end

    def refresh!(&on_progress)
      models_with_names = fetch_models
      reconcile(models_with_names)
      return if %w[openrouter ollama].include?(@provider)
      probe_new_models(&on_progress)
    end

    private

    def fetch_models
      case @provider
      when "openai" then fetch_openai_models
      when "anthropic" then fetch_anthropic_models
      when "openrouter" then fetch_openrouter_models
      when "ollama" then fetch_ollama_models
      else []
      end
    end

    def fetch_connection(base_url)
      Faraday.new(url: base_url) do |f|
        f.options.timeout = 15
        f.options.open_timeout = 5
        f.adapter Faraday.default_adapter
      end
    end

    def fetch_openai_models
      response = fetch_connection("https://api.openai.com").get("/v1/models") do |req|
        req.headers["Authorization"] = "Bearer #{@api_key}"
      end
      return [] unless response.success?
      JSON.parse(response.body).fetch("data", []).map { |e| { id: e["id"], display_name: nil } }
    end

    def fetch_anthropic_models
      response = fetch_connection("https://api.anthropic.com").get("/v1/models?limit=100") do |req|
        req.headers["x-api-key"] = @api_key
        req.headers["anthropic-version"] = "2023-06-01"
      end
      return [] unless response.success?
      JSON.parse(response.body).fetch("data", []).map { |e| { id: e["id"], display_name: e["display_name"] } }
    end

    def fetch_openrouter_models
      response = fetch_connection("https://openrouter.ai").get("/api/v1/models") do |req|
        req.headers["Authorization"] = "Bearer #{@api_key}"
        req.headers["HTTP-Referer"] = "https://completionkit.com"
        req.headers["X-Title"] = "CompletionKit"
      end
      return [] unless response.success?
      JSON.parse(response.body).fetch("data", []).filter_map do |entry|
        next nil if entry["deprecated"] == true
        context_length = entry["context_length"].to_i
        next nil if context_length < 8192
        { id: entry["id"], display_name: entry["name"] }
      end
    end

    def fetch_ollama_models
      return [] if @api_endpoint.nil?
      base_url = @api_endpoint.to_s.delete_suffix("/")
      response = fetch_connection(base_url).get("/models") do |req|
        req.headers["Authorization"] = "Bearer #{@api_key}" if @api_key.present?
      end
      return [] unless response.success?
      JSON.parse(response.body).fetch("data", []).map { |e| { id: e["id"], display_name: e["id"] } }
    end

    def reconcile(models_with_names)
      api_model_ids = models_with_names.map { |m| m[:id] }
      names_by_id = models_with_names.each_with_object({}) { |m, h| h[m[:id]] = m[:display_name] }
      existing = Model.where(provider: @provider).index_by(&:model_id)

      api_model_ids.each do |model_id|
        if existing[model_id]
          attrs = { status: "active", retired_at: nil }
          attrs[:display_name] = names_by_id[model_id] if names_by_id[model_id].present?
          existing[model_id].update!(attrs) if existing[model_id].status == "retired" || names_by_id[model_id].present?
        else
          attrs = {
            provider: @provider,
            model_id: model_id,
            display_name: names_by_id[model_id],
            status: "active",
            discovered_at: Time.current
          }
          if %w[openrouter ollama].include?(@provider)
            attrs[:supports_generation] = true
            attrs[:probed_at] = nil
          end
          Model.create!(attrs)
        end
      end

      active_not_in_api = Model.where(provider: @provider, status: "active")
                               .where.not(model_id: api_model_ids)
      active_not_in_api.update_all(status: "retired", retired_at: Time.current)
    end

    def probe_new_models(&on_progress)
      unprobed = Model.where(provider: @provider, supports_generation: nil, status: "active")
      total = unprobed.count
      current = 0
      unprobed.find_each do |model|
        probe_generation(model)
        probe_judging(model) if model.supports_generation
        model.probed_at = Time.current
        model.status = "failed" if model.supports_generation == false
        model.save!
        current += 1
        on_progress&.call(current, total)
      end
    end

    def probe_generation(model)
      response = send_probe(model.model_id, "Say hello", 20)
      if response.success?
        text = extract_text(response)
        if text.present?
          model.supports_generation = true
        else
          model.supports_generation = false
          model.generation_error = "Empty response"
        end
      else
        model.supports_generation = false
        model.generation_error = "#{response.status} - #{response.body.truncate(500)}"
      end
    rescue StandardError => e
      model.supports_generation = false
      model.generation_error = e.message
    end

    def probe_judging(model)
      judge_input = <<~PROMPT
        You are an expert evaluator. You MUST respond with ONLY two lines in this exact format, nothing else:

        Score: <integer from 1 to 5>
        Feedback: <one sentence explaining why>

        AI output to evaluate: The sky is blue.
      PROMPT

      response = send_probe(model.model_id, judge_input, 50)
      if response.success?
        text = extract_text(response).to_s
        if text.match?(/Score:\s*\d/i)
          model.supports_judging = true
        else
          model.supports_judging = false
          model.judging_error = "Response not in Score/Feedback format: #{text.truncate(200)}"
        end
      else
        model.supports_judging = false
        model.judging_error = "#{response.status} - #{response.body.truncate(500)}"
      end
    rescue StandardError => e
      model.supports_judging = false
      model.judging_error = e.message
    end

    def send_probe(model_id, input, max_tokens)
      if @provider == "openai"
        openai_probe(model_id, input, max_tokens)
      else
        anthropic_probe(model_id, input, max_tokens)
      end
    end

    def extract_text(response)
      data = JSON.parse(response.body)
      if @provider == "openai"
        data.dig("output", 0, "content", 0, "text")
      else
        data.dig("content", 0, "text")
      end
    end

    def openai_probe(model_id, input, max_tokens)
      conn = Faraday.new(url: "https://api.openai.com") do |f|
        f.options.timeout = 15
        f.options.open_timeout = 5
        f.request :retry, max: 1, interval: 0.5
        f.adapter Faraday.default_adapter
      end
      conn.post do |req|
        req.url "/v1/responses"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{@api_key}"
        req.body = { model: model_id, input: input, max_output_tokens: max_tokens, store: false }.to_json
      end
    end

    def anthropic_probe(model_id, input, max_tokens)
      conn = Faraday.new(url: "https://api.anthropic.com") do |f|
        f.options.timeout = 15
        f.options.open_timeout = 5
        f.request :retry, max: 1, interval: 0.5
        f.adapter Faraday.default_adapter
      end
      conn.post do |req|
        req.url "/v1/messages"
        req.headers["Content-Type"] = "application/json"
        req.headers["x-api-key"] = @api_key
        req.headers["anthropic-version"] = "2023-06-01"
        req.body = { model: model_id, messages: [{ role: "user", content: input }], max_tokens: max_tokens }.to_json
      end
    end
  end
end

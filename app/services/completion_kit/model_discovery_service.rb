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
      candidates = Model.where(provider: @provider, status: %w[active failed])
        .where("supports_generation IS NULL OR supports_judging IS NULL OR generation_error IS NOT NULL OR judging_error IS NOT NULL")
      total = candidates.count
      current = 0
      candidates.find_each do |model|
        if model.supports_generation.nil? || model.generation_error.present?
          model.generation_error = nil
          probe_generation(model)
        end
        if model.supports_generation && (model.supports_judging.nil? || model.judging_error.present?)
          model.judging_error = nil
          probe_judging(model)
        end
        model.probed_at = Time.current
        model.status = (model.supports_generation == false ? "failed" : "active")
        model.save!
        current += 1
        on_progress&.call(current, total)
      end
    end

    def probe_generation(model)
      response = send_probe(model.model_id, "Say hello", 65536)
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

      response = send_probe(model.model_id, judge_input, 65536)
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
      case @provider
      when "openai" then openai_probe(model_id, input, max_tokens)
      when "anthropic" then anthropic_probe(model_id, input, max_tokens)
      when "openrouter" then openrouter_probe(model_id, input, max_tokens)
      when "ollama" then ollama_probe(model_id, input, max_tokens)
      else raise ArgumentError, "Unsupported probe provider: #{@provider}"
      end
    end

    def extract_text(response)
      data = JSON.parse(response.body)
      case @provider
      when "openai" then data.dig("output", 0, "content", 0, "text")
      when "anthropic" then data.dig("content", 0, "text")
      else data.dig("choices", 0, "message", "content")
      end
    end

    def openai_probe(model_id, input, max_tokens)
      conn = openai_probe_connection
      response = openai_probe_post(conn, model_id, input, max_tokens, openai_reasoning_effort_for(model_id))
      if response.status == 400 && response.body.to_s.include?("is not supported with the")
        response = openai_probe_post(conn, model_id, input, max_tokens, nil)
      end
      response
    end

    def openai_probe_connection
      Faraday.new(url: "https://api.openai.com") do |f|
        f.options.timeout = 180
        f.options.open_timeout = 5
        f.request :retry, max: 1, interval: 0.5
        f.adapter Faraday.default_adapter
      end
    end

    def openai_probe_post(conn, model_id, input, max_tokens, effort)
      body = { model: model_id, input: input, max_output_tokens: max_tokens, store: false }
      body[:reasoning] = { effort: effort } if effort
      conn.post do |req|
        req.url "/v1/responses"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{@api_key}"
        req.body = body.to_json
      end
    end

    def openai_reasoning_effort_for(model_id)
      return nil unless model_id.to_s.match?(/\A(gpt-5|o1|o3)/)
      "low"
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

    def openrouter_probe(model_id, input, max_tokens)
      conn = Faraday.new(url: "https://openrouter.ai") do |f|
        f.options.timeout = 30
        f.options.open_timeout = 5
        f.request :retry, max: 1, interval: 0.5
        f.adapter Faraday.default_adapter
      end
      conn.post do |req|
        req.url "/api/v1/chat/completions"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{@api_key}"
        req.headers["HTTP-Referer"] = "https://completionkit.com"
        req.headers["X-Title"] = "CompletionKit"
        req.body = { model: model_id, messages: [{ role: "user", content: input }], max_tokens: max_tokens }.to_json
      end
    end

    def ollama_probe(model_id, input, max_tokens)
      base_url = @api_endpoint.to_s.delete_suffix("/")
      conn = Faraday.new(url: base_url) do |f|
        f.options.timeout = 60
        f.options.open_timeout = 5
        f.request :retry, max: 1, interval: 0.5
        f.adapter Faraday.default_adapter
      end
      conn.post do |req|
        req.url "/chat/completions"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{@api_key}" if @api_key.present?
        req.body = { model: model_id, messages: [{ role: "user", content: input }], max_tokens: max_tokens }.to_json
      end
    end
  end
end

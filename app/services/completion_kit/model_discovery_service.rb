require "faraday"
require "faraday/retry"
require "json"

module CompletionKit
  class ModelDiscoveryService
    class DiscoveryError < StandardError; end

    def initialize(config:)
      @provider = config[:provider]
      @api_key = config[:api_key]
      @api_endpoint = config[:api_endpoint]
    end

    def refresh!(force: false, &on_progress)
      discovered = fetch_models
      reconcile(discovered)
      # OpenRouter publishes capability metadata (output modalities, etc.), so we
      # derive everything from the model list and skip live probing entirely.
      # Judging stays unknown ("?") until a real run proves it.
      return if @provider == "openrouter"

      reset_failed_generation if force
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

    def raise_fetch_error!(response)
      label = case response.status
              when 401, 403 then "Invalid API key for #{@provider}"
              when 429 then "Rate limited by #{@provider}"
              when 500..599 then "#{@provider} returned #{response.status}"
              else "#{@provider} model list request failed (#{response.status})"
              end
      detail = extract_provider_error_message(response.body)
      raise DiscoveryError, detail.present? ? "#{label}: #{detail}" : label
    end

    def extract_provider_error_message(body)
      return nil if body.blank?
      data = JSON.parse(body)
      err = data["error"]
      (err.is_a?(Hash) && err["message"]) || data["message"] || (err.is_a?(String) && err) || nil
    rescue JSON::ParserError
      body.to_s.truncate(200)
    end

    def fetch_openai_models
      response = fetch_connection("https://api.openai.com").get("/v1/models") do |req|
        req.headers["Authorization"] = "Bearer #{@api_key}"
      end
      raise_fetch_error!(response) unless response.success?
      JSON.parse(response.body).fetch("data", []).map { |e| { id: e["id"], display_name: nil } }
    end

    def fetch_anthropic_models
      response = fetch_connection("https://api.anthropic.com").get("/v1/models?limit=100") do |req|
        req.headers["x-api-key"] = @api_key
        req.headers["anthropic-version"] = "2023-06-01"
      end
      raise_fetch_error!(response) unless response.success?
      JSON.parse(response.body).fetch("data", []).map { |e| { id: e["id"], display_name: e["display_name"] } }
    end

    def fetch_openrouter_models
      response = fetch_connection("https://openrouter.ai").get("/api/v1/models") do |req|
        req.headers["Authorization"] = "Bearer #{@api_key}"
        req.headers["HTTP-Referer"] = "https://completionkit.com"
        req.headers["X-Title"] = "CompletionKit"
      end
      raise_fetch_error!(response) unless response.success?
      JSON.parse(response.body).fetch("data", []).filter_map do |entry|
        next nil if entry["deprecated"] == true
        context_length = entry["context_length"].to_i
        next nil if context_length < 8192
        { id: entry["id"], display_name: entry["name"], supports_generation: openrouter_text_output?(entry) }
      end
    end

    # OpenRouter exposes architecture.output_modalities (e.g. ["text"], ["image"],
    # ["text", "image"]). A model can be used for generation/judging only if it
    # outputs text. When the field is missing we keep the historical default of
    # treating the model as text-capable.
    def openrouter_text_output?(entry)
      modalities = Array(entry.dig("architecture", "output_modalities")).map(&:to_s)
      modalities.empty? || modalities.include?("text")
    end

    def fetch_ollama_models
      raise DiscoveryError, "Ollama endpoint URL is required" if @api_endpoint.blank?
      base_url = ollama_root_url
      response = fetch_connection(base_url).get("/v1/models") do |req|
        req.headers["Authorization"] = "Bearer #{@api_key}" if @api_key.present?
      end
      raise_fetch_error!(response) unless response.success?
      JSON.parse(response.body).fetch("data", []).map { |e| { id: e["id"], display_name: e["id"] } }
    end

    def ollama_root_url
      @api_endpoint.to_s.strip.delete_suffix("/").delete_suffix("/v1")
    end

    def reconcile(discovered)
      api_model_ids = discovered.map { |m| m[:id] }
      meta_by_id = discovered.index_by { |m| m[:id] }
      existing = Model.where(provider: @provider).index_by(&:model_id)

      api_model_ids.each do |model_id|
        meta = meta_by_id[model_id]
        if (model = existing[model_id])
          reconcile_existing_model(model, meta)
        else
          Model.create!(new_model_attrs(model_id, meta))
        end
      end

      Model.where(provider: @provider, status: "active")
           .where.not(model_id: api_model_ids)
           .update_all(status: "retired", retired_at: Time.current)
    end

    def new_model_attrs(model_id, meta)
      attrs = {
        provider: @provider,
        model_id: model_id,
        display_name: meta[:display_name],
        status: "active",
        discovered_at: Time.current
      }
      if @provider == "openrouter"
        supports_generation = meta[:supports_generation] != false
        attrs.merge!(
          supports_generation: supports_generation,
          supports_judging: nil,
          probed_at: Time.current,
          status: supports_generation ? "active" : "failed"
        )
      elsif @provider == "ollama"
        attrs[:supports_generation] = true
        attrs[:probed_at] = nil
      end
      attrs
    end

    def reconcile_existing_model(model, meta)
      if @provider == "openrouter"
        # Re-derive generation capability from the published metadata every refresh
        # (fixes models discovered before capability metadata was used). Leave
        # supports_judging alone — it's "learned" from successful runs.
        supports_generation = meta[:supports_generation] != false
        model.update!(
          display_name: meta[:display_name].presence || model.display_name,
          supports_generation: supports_generation,
          generation_error: nil,
          probed_at: Time.current,
          status: supports_generation ? "active" : "failed",
          retired_at: nil
        )
      else
        attrs = { status: "active", retired_at: nil }
        attrs[:display_name] = meta[:display_name] if meta[:display_name].present?
        model.update!(attrs) if model.status == "retired" || meta[:display_name].present?
      end
    end

    def reset_failed_generation
      Model.where(provider: @provider, status: %w[active failed], supports_generation: false)
           .update_all(supports_generation: nil, generation_error: nil)
    end

    def probe_new_models(&on_progress)
      candidates = Model.where(provider: @provider, status: %w[active failed])
        .where("supports_generation IS NULL OR supports_judging IS NULL OR (generation_error IS NOT NULL AND #{retryable_error_sql('generation_error')}) OR (judging_error IS NOT NULL AND #{retryable_error_sql('judging_error')})")
      total = candidates.count
      current = 0
      candidates.find_each do |model|
        probed = false
        if model.supports_generation.nil? || retryable_error?(model.generation_error)
          model.generation_error = nil
          probe_generation(model)
          probed = true
        end
        if model.supports_generation && (model.supports_judging.nil? || retryable_error?(model.judging_error))
          model.judging_error = nil
          probe_judging(model)
          probed = true
        end
        if probed
          model.probed_at = Time.current
          model.status = (model.supports_generation == false ? "failed" : "active")
          model.save!
        end
        current += 1
        on_progress&.call(current, total)
      end
    end

    def retryable_error?(error_string)
      return false if error_string.blank?
      return true if error_string.start_with?("429 ")
      !error_string.match?(/\A4\d\d\s/)
    end

    def retryable_error_sql(column)
      "(#{column} LIKE '429 -%' OR #{column} NOT LIKE '4__ -%')"
    end

    def probe_generation(model)
      probe_input = "Reply with exactly this token and nothing else: PING-OK"
      response = send_probe(model.model_id, probe_input, probe_max_output_tokens)
      if response.success?
        text = extract_text(response).to_s
        if text.blank?
          model.supports_generation = false
          model.generation_error = "Empty response"
        elsif text.include?("PING-OK")
          model.supports_generation = true
        else
          model.supports_generation = false
          model.generation_error = "Did not follow text completion instruction (likely non-text-output model): #{text.truncate(200)}"
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

      response = send_probe(model.model_id, judge_input, probe_max_output_tokens)
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

    OPENAI_REASONING_PROBE_BUDGET = 65_536
    CHAT_PROBE_BUDGET = 1_024

    def probe_max_output_tokens
      @provider == "openai" ? OPENAI_REASONING_PROBE_BUDGET : CHAT_PROBE_BUDGET
    end

    def send_probe(model_id, input, max_tokens)
      case @provider
      when "openai" then openai_probe(model_id, input, max_tokens)
      when "anthropic" then anthropic_probe(model_id, input, max_tokens)
      when "ollama" then ollama_probe(model_id, input, max_tokens)
      else raise ArgumentError, "Unsupported probe provider: #{@provider}"
      end
    end

    def extract_text(response)
      data = JSON.parse(response.body)
      case @provider
      when "openai"
        message = Array(data["output"]).find { |o| o["type"] == "message" }
        message&.dig("content", 0, "text")
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

    def ollama_probe(model_id, input, max_tokens)
      conn = Faraday.new(url: ollama_root_url) do |f|
        f.options.timeout = 60
        f.options.open_timeout = 5
        f.request :retry, max: 1, interval: 0.5
        f.adapter Faraday.default_adapter
      end
      conn.post do |req|
        req.url "/v1/chat/completions"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{@api_key}" if @api_key.present?
        req.body = { model: model_id, messages: [{ role: "user", content: input }], max_tokens: max_tokens }.to_json
      end
    end
  end
end

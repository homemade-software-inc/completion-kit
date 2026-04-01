require "faraday"
require "faraday/retry"
require "json"

module CompletionKit
  class ModelDiscoveryService
    def initialize(config:)
      @provider = config[:provider]
      @api_key = config[:api_key]
    end

    def refresh!
      api_model_ids = fetch_model_ids
      reconcile(api_model_ids)
      probe_new_models
    end

    private

    def fetch_model_ids
      response = Faraday.get("https://api.openai.com/v1/models") do |req|
        req.headers["Authorization"] = "Bearer #{@api_key}"
      end

      return [] unless response.success?

      JSON.parse(response.body).fetch("data", []).map { |entry| entry["id"] }
    rescue StandardError
      []
    end

    def reconcile(api_model_ids)
      existing = Model.where(provider: @provider).index_by(&:model_id)

      api_model_ids.each do |model_id|
        if existing[model_id]
          existing[model_id].update!(status: "active", retired_at: nil) if existing[model_id].status == "retired"
        else
          Model.create!(
            provider: @provider,
            model_id: model_id,
            status: "active",
            discovered_at: Time.current
          )
        end
      end

      active_not_in_api = Model.where(provider: @provider, status: "active")
                               .where.not(model_id: api_model_ids)
      active_not_in_api.update_all(status: "retired", retired_at: Time.current)
    end

    def probe_new_models
      Model.where(provider: @provider, supports_generation: nil, status: "active").find_each do |model|
        probe_generation(model)
        probe_judging(model) if model.supports_generation
        model.probed_at = Time.current
        model.status = "failed" if model.supports_generation == false
        model.save!
      end
    end

    def probe_generation(model)
      response = responses_api_call(model.model_id, "Say hello", max_output_tokens: 20)

      if response.success?
        data = JSON.parse(response.body)
        text = data.dig("output", 0, "content", 0, "text")
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

      response = responses_api_call(model.model_id, judge_input, max_output_tokens: 50)

      if response.success?
        data = JSON.parse(response.body)
        text = data.dig("output", 0, "content", 0, "text").to_s
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

    def responses_api_call(model_id, input, max_output_tokens: 10)
      conn = Faraday.new(url: "https://api.openai.com") do |f|
        f.request :retry, max: 1, interval: 0.5
        f.adapter Faraday.default_adapter
      end

      conn.post do |req|
        req.url "/v1/responses"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{@api_key}"
        req.body = {
          model: model_id,
          input: input,
          max_output_tokens: max_output_tokens,
          store: false
        }.to_json
      end
    end
  end
end

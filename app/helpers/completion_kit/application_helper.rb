module CompletionKit
  module ApplicationHelper
    def ck_button_classes(tone = :dark, variant: :solid)
      base = "ck-button"

      styles = case [tone, variant]
               when [:dark, :solid]
                 "ck-button--primary"
               when [:light, :outline]
                 "ck-button--secondary"
               when [:green, :solid]
                 "ck-button--success"
               when [:red, :outline]
                 "ck-button--danger"
               when [:amber, :outline]
                 "ck-button--warning"
               when [:blue, :outline]
                 "ck-button--info"
               else
                 "ck-button--primary"
               end

      "#{base} #{styles}"
    end

    def ck_badge_classes(kind)
      case kind.to_s
      when "high"
        "ck-badge ck-badge--high"
      when "medium"
        "ck-badge ck-badge--medium"
      when "low"
        "ck-badge ck-badge--low"
      when "pending"
        "ck-badge ck-badge--pending"
      when "running"
        "ck-badge ck-badge--running"
      when "generating", "judging"
        "ck-badge ck-badge--running"
      when "completed"
        "ck-badge ck-badge--high"
      when "failed"
        "ck-badge ck-badge--low"
      else
        "ck-badge ck-badge--pending"
      end
    end

    def ck_run_dot(run)
      if run.status == "pending"
        "ck-dot ck-dot--pending"
      elsif run.status == "generating" || run.status == "judging"
        "ck-dot ck-dot--running"
      elsif run.status == "failed"
        "ck-dot ck-dot--failed"
      elsif run.status == "completed"
        avg = run.avg_score
        if avg
          "ck-dot ck-dot--#{ck_score_kind(avg)}"
        else
          "ck-dot ck-dot--completed"
        end
      else
        "ck-dot ck-dot--pending"
      end
    end

    PROVIDER_LABELS = { "openai" => "OpenAI", "anthropic" => "Anthropic", "llama" => "Llama" }.freeze

    def ck_provider_label(provider)
      PROVIDER_LABELS[provider.to_s] || provider.to_s.titleize
    end

    def ck_grouped_models(models, selected = nil)
      if selected.present? && models.none? { |m| m[:id] == selected }
        retired = CompletionKit::Model.find_by(model_id: selected)
        if retired
          models = models + [{ id: retired.model_id, name: "#{retired.display_name || retired.model_id} (retired)", provider: retired.provider }]
        end
      end
      groups = models.group_by { |m| m[:provider] }.map do |provider, ms|
        [ck_provider_label(provider), ms.map { |m| [m[:name], m[:id]] }]
      end
      grouped_options_for_select(groups, selected)
    end

    def ck_model_options_html(scope)
      models = CompletionKit::ApiConfig.available_models(scope: scope)
      return "" if models.empty?
      ck_grouped_models(models)
    end

    def ck_score_kind(score)
      return :pending if score.nil?
      return :high if score >= CompletionKit.config.high_quality_threshold
      return :medium if score >= CompletionKit.config.medium_quality_threshold

      :low
    end
  end
end

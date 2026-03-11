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

    def ck_score_kind(score)
      return :pending if score.nil?
      return :high if score >= CompletionKit.config.high_quality_threshold
      return :medium if score >= CompletionKit.config.medium_quality_threshold

      :low
    end
  end
end

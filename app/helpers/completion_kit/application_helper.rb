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
      case run.status
      when "generating", "judging" then "ck-dot ck-dot--running"
      when "failed" then "ck-dot ck-dot--failed"
      when "completed" then "ck-dot ck-dot--completed"
      else "ck-dot ck-dot--pending"
      end
    end

    def ck_run_status_label(run)
      case run.status
      when "pending" then "Ready to run"
      when "generating"
        if run.progress_total.to_i > 0
          "Generating responses (#{run.progress_current}/#{run.progress_total})"
        else
          "Generating responses…"
        end
      when "judging"
        if run.progress_total.to_i > 0
          "Judging (#{run.progress_current}/#{run.progress_total} evaluations)"
        else
          "Judging…"
        end
      when "completed" then "Completed"
      when "failed" then "Failed"
      else run.status.capitalize
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

    def ck_word_diff_old(old_text, new_text)
      diff_tokens(old_text, new_text, :old)
    end

    def ck_word_diff_new(old_text, new_text)
      diff_tokens(old_text, new_text, :new)
    end

    private

    def diff_tokens(old_text, new_text, side)
      old_words = tokenize_for_diff(old_text)
      new_words = tokenize_for_diff(new_text)
      lcs = lcs_table(old_words, new_words)
      result = []
      i = old_words.length
      j = new_words.length

      changes = []
      while i > 0 || j > 0
        if i > 0 && j > 0 && old_words[i - 1] == new_words[j - 1]
          changes.unshift([:equal, old_words[i - 1]])
          i -= 1
          j -= 1
        elsif j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j])
          changes.unshift([:add, new_words[j - 1]])
          j -= 1
        else
          changes.unshift([:remove, old_words[i - 1]])
          i -= 1
        end
      end

      changes.each do |type, token|
        escaped = ERB::Util.html_escape(token)
        if type == :equal
          result << escaped
        elsif type == :remove && side == :old
          result << content_tag(:span, escaped, class: "ck-diff-del")
        elsif type == :add && side == :new
          result << content_tag(:span, escaped, class: "ck-diff-ins")
        end
      end

      result.join.html_safe
    end

    def tokenize_for_diff(text)
      text.to_s.scan(/\S+|\n| +/)
    end

    def lcs_table(a, b)
      m = a.length
      n = b.length
      table = Array.new(m + 1) { Array.new(n + 1, 0) }
      (1..m).each do |i|
        (1..n).each do |j|
          table[i][j] = if a[i - 1] == b[j - 1]
                          table[i - 1][j - 1] + 1
                        else
                          [table[i - 1][j], table[i][j - 1]].max
                        end
        end
      end
      table
    end
  end
end

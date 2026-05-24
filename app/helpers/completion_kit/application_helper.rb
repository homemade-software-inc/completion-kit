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
      when "running" then "ck-dot ck-dot--running"
      when "failed" then "ck-dot ck-dot--failed"
      when "completed" then "ck-dot ck-dot--completed"
      else "ck-dot ck-dot--pending"
      end
    end

    def ck_run_status_label(run)
      case run.status
      when "pending" then "Ready to run"
      when "running"
        if run.progress_total.to_i > 0
          "Running (#{run.progress_current}/#{run.progress_total})"
        else
          "Running…"
        end
      when "completed" then "Completed"
      when "failed" then "Failed"
      else run.status.capitalize
      end
    end

    def ck_provider_label(provider)
      CompletionKit::ProviderCredential::PROVIDER_LABELS[provider.to_s] || provider.to_s.titleize
    end

    def ck_masked_token(token)
      return "YOUR_TOKEN" if token.blank?
      return "••••••••" if token.length < 12
      "#{token[0..3]}#{'•' * [token.length - 8, 4].max}#{token[-4..]}"
    end

    OPENAI_MODEL_FAMILY_ORDER = ["GPT-5", "GPT-4", "o-series", "GPT-3.5", "GPT-OSS", "Other"].freeze

    def ck_openai_model_family(model_id)
      id = model_id.to_s
      return "GPT-5" if id.match?(/\Agpt-5/i)
      return "GPT-4" if id.match?(/\Agpt-4/i)
      return "GPT-3.5" if id.match?(/\Agpt-3/i)
      return "GPT-OSS" if id.match?(/\Agpt-oss/i)
      return "o-series" if id.match?(/\Ao\d/i)
      "Other"
    end

    # Groups a provider's models for the models-card table, mirroring how the
    # dropdown sub-groups: OpenRouter clusters by upstream vendor (the part
    # before "/"); OpenAI clusters by family; everyone else stays flat. Returns
    # [[section_label_or_nil, [models]], ...]. A single section collapses to a
    # nil label so we don't render a redundant header.
    def ck_model_table_sections(models)
      models = models.to_a
      sections =
        case models.first&.provider
        when "openrouter"
          models.group_by { |m| m.model_id.to_s.split("/", 2).first.delete_prefix("~") }
                .sort_by { |label, _| label }
        when "openai"
          grouped = models.group_by { |m| ck_openai_model_family(m.model_id) }
          ordered = OPENAI_MODEL_FAMILY_ORDER.filter_map { |label| [label, grouped[label]] if grouped[label] }
          extras = (grouped.keys - OPENAI_MODEL_FAMILY_ORDER).sort.map { |label| [label, grouped[label]] }
          ordered + extras
        else
          [[nil, models]]
        end
      sections.size <= 1 ? [[nil, models]] : sections
    end

    def ck_model_option_label(model)
      return "#{model[:name]} (?)" if model.key?(:judging_confirmed) && !model[:judging_confirmed]
      model[:name]
    end

    def ck_grouped_models(models, selected = nil)
      if selected.present? && models.none? { |m| m[:id] == selected }
        retired = CompletionKit::Model.find_by(model_id: selected)
        if retired
          models = models + [{ id: retired.model_id, name: "#{retired.display_name || retired.model_id} (retired)", provider: retired.provider }]
        end
      end

      groups = models.group_by { |m| ck_model_optgroup_label(m) }
      ordered_keys = groups.keys.sort_by { |label| ck_model_optgroup_sort_key(label) }
      grouped = ordered_keys.map { |label| [label, groups[label].map { |m| [ck_model_option_label(m), m[:id]] }] }
      grouped_options_for_select(grouped, selected)
    end

    # Optgroup label for the model select — mirrors the provider models table:
    # OpenRouter splits by upstream vendor, OpenAI splits by family, everyone
    # else is a single group.
    def ck_model_optgroup_label(model)
      case model[:provider]
      when "openrouter" then "OpenRouter — #{model[:id].to_s.split("/", 2).first.delete_prefix("~")}"
      when "openai"     then "OpenAI — #{ck_openai_model_family(model[:id])}"
      else ck_provider_label(model[:provider])
      end
    end

    def ck_model_optgroup_sort_key(label)
      if label.start_with?("OpenAI — ")
        [0, OPENAI_MODEL_FAMILY_ORDER.index(label.delete_prefix("OpenAI — ")), label]
      elsif label.start_with?("OpenRouter")
        [2, 0, label]
      else
        [1, 0, label]
      end
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

    def tag_pill_class(tag, outline: false)
      ["tag", "tag-#{tag.color}", ("tag-outline" if outline)].compact.join(" ")
    end

    def ck_run_path(run)
      CompletionKit::Engine.routes.url_helpers.run_path(run, **ck_engine_path_options)
    end

    def ck_prompt_path(prompt)
      CompletionKit::Engine.routes.url_helpers.prompt_path(prompt, **ck_engine_path_options)
    end

    def ck_dataset_path(dataset)
      CompletionKit::Engine.routes.url_helpers.dataset_path(dataset, **ck_engine_path_options)
    end

    # Dynamic route segments owned by the host's mount scope (e.g. an
    # `org_slug` from `scope "/orgs/:org_slug"`) live in `url_options[:_recall]`.
    # The engine's url_helpers won't read them out of the nested recall hash to
    # satisfy a required segment — they have to arrive as explicit kwargs.
    def ck_engine_path_options
      (url_options[:_recall] || {}).except(:controller, :action)
    end

    def ck_format_maybe_json(text)
      s = text.to_s
      return s if s.strip.empty?
      payload = ck_unwrap_json_fence(s.strip)
      first = payload[0]
      return s unless first == "{" || first == "["
      begin
        ck_highlight_json(JSON.pretty_generate(JSON.parse(payload)))
      rescue JSON::ParserError
        s
      end
    end

    def ck_unwrap_json_fence(text)
      m = text.match(/\A```(?:json|JSON)?\s*\n(.*?)\n?```\s*\z/m)
      m ? m[1].strip : text
    end

    def ck_highlight_json(text)
      tokens = ck_tokenize_json(text)
      is_key = ck_mark_json_keys(tokens)
      parts = tokens.each_with_index.map do |(type, value), idx|
        escaped = ERB::Util.html_escape(value)
        case type
        when :punct then %(<span class="ck-json-punct">#{escaped}</span>)
        when :string
          %(<span class="#{is_key[idx] ? "ck-json-key" : "ck-json-string"}">#{escaped}</span>)
        when :number then %(<span class="ck-json-number">#{escaped}</span>)
        when :keyword then %(<span class="ck-json-keyword">#{escaped}</span>)
        else escaped
        end
      end
      parts.join.html_safe
    end

    def ck_tokenize_json(text)
      tokens = []
      i = 0
      len = text.length
      while i < len
        ch = text[i]
        if ch == " " || ch == "\n" || ch == "\t"
          tokens << [:ws, ch]
          i += 1
        elsif "{}[]:,".include?(ch)
          tokens << [:punct, ch]
          i += 1
        elsif ch == '"'
          j = i + 1
          while j < len && text[j] != '"'
            j += text[j] == "\\" ? 2 : 1
          end
          j = len - 1 if j >= len
          tokens << [:string, text[i..j]]
          i = j + 1
        elsif ch == "-" || (ch >= "0" && ch <= "9")
          j = i + 1
          j += 1 while j < len && "0123456789.eE+-".include?(text[j])
          tokens << [:number, text[i...j]]
          i = j
        elsif text[i, 4] == "true" || text[i, 4] == "null"
          tokens << [:keyword, text[i, 4]]
          i += 4
        elsif text[i, 5] == "false"
          tokens << [:keyword, "false"]
          i += 5
        else
          tokens << [:other, ch]
          i += 1
        end
      end
      tokens
    end

    def ck_mark_json_keys(tokens)
      tokens.each_with_index.map do |(type, _), idx|
        next false unless type == :string
        j = idx + 1
        j += 1 while j < tokens.length && tokens[j][0] == :ws
        j < tokens.length && tokens[j] == [:punct, ":"]
      end
    end

    def tag_filter_url(base_path, selected, toggling)
      remaining = selected.reject { |t| t.id == toggling.id }
      next_set = selected.include?(toggling) ? remaining : remaining + [toggling]
      return base_path if next_set.empty?
      "#{base_path}?#{{ tag: next_set.map(&:name) }.to_query}"
    end

    def ck_field_aria(form, field)
      return {} unless form.object.errors[field].any?
      { "aria-invalid" => "true", "aria-describedby" => ck_field_error_id(form, field) }
    end

    def ck_field_error(form, field)
      return nil unless form.object.errors[field].any?
      content_tag(:p, form.object.errors[field].first, class: "ck-field-error", id: ck_field_error_id(form, field))
    end

    def ck_field_error_id(form, field)
      "#{form.object.model_name.param_key}_#{field}_error"
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

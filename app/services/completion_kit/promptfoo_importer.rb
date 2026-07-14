require "yaml"
require "csv"

module CompletionKit
  class PromptfooImporter
    Result = Data.define(:ok, :error, :prompts, :dataset, :metrics, :providers)

    JUDGE_ASSERTS = %w[llm-rubric g-eval model-graded-closedqa factuality].freeze

    def self.call(content)
      new(content).call
    end

    def initialize(content)
      @content = content.to_s
    end

    def call
      config = parse
      return failure("Could not parse YAML: #{@parse_error}") if config.nil?
      return failure("Top-level YAML must be a mapping of promptfoo config keys.") unless config.is_a?(Hash)

      ApplicationRecord.transaction do
        providers = import_providers(config)
        prompts = import_prompts(config, default_model(config))
        dataset = import_dataset(config)
        metrics = import_metrics(config)
        Result.new(ok: true, error: nil, prompts: prompts, dataset: dataset, metrics: metrics, providers: providers)
      end
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence.presence || e.message)
    end

    private

    def parse
      YAML.safe_load(@content, aliases: true)
    rescue Psych::Exception => e
      @parse_error = e.message
      nil
    end

    def failure(message)
      Result.new(ok: false, error: message, prompts: nil, dataset: nil, metrics: nil, providers: nil)
    end

    def import_providers(config)
      entries = Array(config["providers"]).map { |p| provider_name(p) }.compact
      configured = ProviderCredential.pluck(:provider).to_set
      matched = []
      unmatched = []
      entries.each do |entry|
        provider = entry.split(":").first
        (configured.include?(provider) ? matched : unmatched) << entry
      end
      { matched: matched.uniq, unmatched: unmatched.uniq }
    end

    def provider_name(provider)
      provider.is_a?(Hash) ? provider["id"] : provider
    end

    def default_model(config)
      first = Array(config["providers"]).map { |p| provider_name(p) }.compact.first
      return "gpt-4o" if first.nil?

      parts = first.split(":")
      parts.length > 1 ? parts.last : first
    end

    def import_prompts(config, model)
      created = []
      skipped = []
      Array(config["prompts"]).each_with_index do |raw, index|
        if raw.is_a?(String) && raw.start_with?("file://")
          skipped << { value: raw, reason: "prompt file reference; paste the file's contents to import it" }
          next
        end
        template = prompt_template(raw)
        if template.nil?
          skipped << { value: raw.inspect, reason: "unsupported prompt shape (only inline string templates import)" }
          next
        end

        prompt = Prompt.create!(name: "Imported prompt #{index + 1}", template: template, llm_model: model)
        created << prompt.name
      end
      { created: created, skipped: skipped }
    end

    def prompt_template(raw)
      return raw if raw.is_a?(String)
      raw["raw"] || raw["template"] if raw.is_a?(Hash)
    end

    def import_dataset(config)
      tests = Array(config["tests"])
      vars_rows = tests.map { |t| (t.is_a?(Hash) ? t["vars"] : nil) || {} }.select { |v| v.is_a?(Hash) }
      return { skipped: "no tests with vars to import" } if vars_rows.empty?

      columns = vars_rows.flat_map(&:keys).uniq
      csv = CSV.generate do |out|
        out << columns
        vars_rows.each { |vars| out << columns.map { |c| vars[c] } }
      end
      dataset = Dataset.create!(name: "Imported dataset", csv_data: csv)
      { created: dataset.name, rows: vars_rows.length, columns: columns }
    end

    def import_metrics(config)
      created = []
      skipped = []
      asserts(config).each do |assert|
        attrs = metric_attributes(assert)
        if attrs.nil?
          skipped << { type: assert["type"], reason: "no CompletionKit metric maps to this assert type" }
          next
        end

        metric = Metric.create!(attrs)
        created << { name: metric.name, type: metric.metric_type }
      rescue ActiveRecord::RecordInvalid => e
        skipped << { type: assert["type"], reason: e.record.errors.full_messages.join(", ") }
      end
      { created: created, skipped: skipped }
    end

    def asserts(config)
      default = config.dig("defaultTest", "assert")
      per_test = Array(config["tests"]).flat_map { |t| t.is_a?(Hash) ? Array(t["assert"]) : [] }
      (Array(default) + per_test).select { |a| a.is_a?(Hash) && a["type"] }.uniq
    end

    def metric_attributes(assert)
      type = assert["type"].to_s
      value = assert["value"]
      return { name: unique_name("Rubric"), metric_type: "llm_judge", instruction: value.to_s } if JUDGE_ASSERTS.include?(type)

      config, label = check_mapping(type, value.to_s)
      return nil if config.nil?

      { name: unique_name(label), metric_type: "check", check_config: config }
    end

    def check_mapping(type, text)
      case type
      when "contains"
        [{ "check_kind" => "contains", "target" => "response_text", "value" => text }, "Contains #{text.truncate(30).inspect}"]
      when "icontains"
        [{ "check_kind" => "contains", "target" => "response_text", "value" => text, "case_sensitive" => false }, "Contains #{text.truncate(30).inspect}"]
      when "not-contains"
        [{ "check_kind" => "not_contains", "target" => "response_text", "value" => text }, "Does not contain #{text.truncate(30).inspect}"]
      when "not-icontains"
        [{ "check_kind" => "not_contains", "target" => "response_text", "value" => text, "case_sensitive" => false }, "Does not contain #{text.truncate(30).inspect}"]
      when "equals"
        [{ "check_kind" => "equals", "target" => "response_text", "value" => text }, "Equals #{text.truncate(30).inspect}"]
      when "regex"
        [{ "check_kind" => "regex", "target" => "response_text", "pattern" => text }, "Matches /#{text.truncate(30)}/"]
      when "is-json"
        [{ "check_kind" => "valid_json", "target" => "response_text" }, "Valid JSON"]
      end
    end

    def unique_name(base)
      @used_names ||= Metric.pluck(:name).to_set
      candidate = base
      counter = 2
      while @used_names.include?(candidate)
        candidate = "#{base} (#{counter})"
        counter += 1
      end
      @used_names << candidate
      candidate
    end
  end
end

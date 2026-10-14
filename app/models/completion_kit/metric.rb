module CompletionKit
  class Metric < ApplicationRecord
    include CompletionKit::Taggable

    DEFAULT_RUBRIC_BANDS = [
      { "stars" => 5, "description" => "Fully meets or exceeds all criteria. No meaningful issues." },
      { "stars" => 4, "description" => "Meets criteria well. Minor issues only." },
      { "stars" => 3, "description" => "Meets criteria adequately. Some room for improvement." },
      { "stars" => 2, "description" => "Partially meets criteria. Significant gaps or frequent errors." },
      { "stars" => 1, "description" => "Fails to meet the criteria. Major errors or completely off-target." }
    ].freeze

    has_many :metric_group_memberships, dependent: :destroy
    has_many :metric_groups, through: :metric_group_memberships, source: :metric_group
    has_many :metric_versions, dependent: :destroy
    has_many :run_metrics, dependent: :destroy
    has_many :reviews, dependent: :nullify
    has_many :dashboard_dismissals, as: :dismissable, dependent: :destroy

    METRIC_TYPES = %w[llm_judge check].freeze

    serialize :rubric_bands, coder: JSON
    serialize :check_config, coder: JSON

    validates :name, presence: true
    validates :key, tenant_scoped_uniqueness: { allow_nil: true }
    validates :metric_type, inclusion: { in: METRIC_TYPES }
    validates :instruction, presence: { message: "can't be blank. An LLM judge needs a rubric to score against." }, if: :llm_judge?
    validate :validate_check_config, if: :check?
    validate :metric_type_immutable_once_in_use, on: :update

    before_validation :generate_key
    before_validation :default_check_target, if: :check?
    before_validation :normalize_rubric_bands, if: :llm_judge?
    before_validation :set_defaults, if: :llm_judge?

    def self.default_rubric_bands
      DEFAULT_RUBRIC_BANDS.map(&:dup)
    end

    def self.default_rubric_text
      rubric_text_for(default_rubric_bands)
    end

    def self.rubric_text_for(bands)
      Array(bands).sort_by { |b| -(b["stars"] || 0) }.map do |band|
        stars = band["stars"].to_i
        label = stars == 1 ? "1 star" : "#{stars} stars"
        "#{label}: #{band["description"]}"
      end.join("\n\n")
    end

    def self.normalize_rubric_bands(raw_bands)
      bands = raw_bands.is_a?(Hash) ? raw_bands.values : Array(raw_bands)
      band_map = bands.each_with_object({}) do |band, acc|
        next unless band.respond_to?(:to_h)

        normalized = band.to_h.stringify_keys.slice("stars", "description")
        stars = normalized["stars"].to_i
        next unless (1..5).cover?(stars)

        acc[stars] = {
          "stars" => stars,
          "description" => normalized["description"].to_s.strip
        }
      end

      default_rubric_bands.map do |default_band|
        stars = default_band["stars"]
        band = band_map[stars]
        {
          "stars" => stars,
          "description" => band && band["description"].present? ? band["description"] : default_band["description"]
        }
      end
    end

    def rubric_bands_for_form
      self.class.normalize_rubric_bands(rubric_bands)
    end

    def display_rubric_text
      self.class.rubric_text_for(rubric_bands_for_form)
    end

    def check?
      metric_type == "check"
    end

    def llm_judge?
      !check?
    end

    def in_use?
      RunMetric.exists?(metric_id: id) || reviews.exists? || metric_versions.exists?
    end

    def as_json(options = {})
      base = {
        id: id, name: name, key: key, metric_type: metric_type,
        created_at: created_at, updated_at: updated_at,
        tags: tags.as_json
      }
      if check?
        base.merge(check_config: check_config)
      else
        base.merge(instruction: instruction, rubric_bands: rubric_bands)
      end
    end

    private

    def generate_key
      self.key ||= name.parameterize if name.present?
    end

    def metric_type_immutable_once_in_use
      return unless metric_type_changed?
      return unless in_use?

      errors.add(:metric_type, "cannot change once the metric has been used in a run")
    end

    def validate_check_config
      config = check_config
      unless config.is_a?(Hash)
        errors.add(:check_config, "must be a configuration object")
        return
      end

      kind = config["check_kind"]
      unless CompletionKit::Checks::Registry.kinds.include?(kind)
        errors.add(:check_config, "needs #{check_label("check_kind")} to be one of #{CompletionKit::Checks::Registry.kinds.join(", ")}")
        return
      end

      validate_check_target(config)
      validate_check_compare_to(config, kind)
      validate_check_required_keys(config, kind)
      if refused_list_value?(config, kind)
        errors.add(:check_config, "needs #{check_label("value", kind)} to be a single value, since only list_overlap takes a list")
      else
        validate_check_kind_rules(config, kind)
      end
    end

    def refused_list_value?(config, kind)
      config["value"].is_a?(Array) && kind != "list_overlap" && will_save_change_to_check_config?
    end

    def validate_check_compare_to(config, kind)
      return unless config.key?("compare_to")

      unless %w[constant expected].include?(config["compare_to"])
        errors.add(:check_config, "needs #{check_label("compare_to")} to be constant or expected")
        return
      end
      if config["compare_to"] == "expected" && !CompletionKit::Checks::Registry.compares_value?(kind)
        errors.add(:check_config, "can grade against \"Each row's expected value\" only with #{CompletionKit::Checks::Registry.comparable_kinds.join(", ")}")
      end
    end

    def validate_check_target(config)
      target = config["target"].presence || "response_text"
      path_given = config["target_path"].present?
      if !CompletionKit::Checks::TargetResolver::TARGETS.include?(target)
        errors.add(:check_config, "needs #{check_label("target")} to be one of #{CompletionKit::Checks::TargetResolver::TARGETS.join(", ")}")
      elsif target == "json_path" && !path_given
        errors.add(:check_config, "needs #{check_label("target_path")} filled in to check a value from the response JSON")
      elsif target != "json_path" && path_given && will_save_change_to_check_config?
        errors.add(:check_config, "needs #{check_label("target")} to be \"#{CompletionKit::Checks::Labels.target("json_path")}\" when #{check_label("target_path")} is filled in")
      end
    end

    def default_check_target
      config = check_config
      return unless config.is_a?(Hash) && config["target"].blank? && config["target_path"].present? && will_save_change_to_check_config?

      self.check_config = config.merge("target" => "json_path")
    end

    def validate_check_required_keys(config, kind)
      required = CompletionKit::Checks::Registry.required_keys.fetch(kind)
      required -= [CompletionKit::Checks::Registry.expected_key(kind)] if config["compare_to"] == "expected" && CompletionKit::Checks::Registry.compares_value?(kind)
      required.each do |required_key|
        missing = required_key == "expected" ? !config.key?("expected") : config[required_key].to_s.strip.empty?
        errors.add(:check_config, "needs #{check_label(required_key, kind)} filled in") if missing
      end
    end

    def validate_check_kind_rules(config, kind)
      case kind
      when "regex"
        validate_check_pattern(config)
      when "list_overlap"
        validate_check_list_overlap(config)
      when "numeric_equals"
        validate_check_numeric_equals(config)
      end
      validate_check_bounds(config, kind) if CompletionKit::Checks::Registry.bounded?(kind)
    end

    def validate_check_pattern(config)
      Regexp.new(config["pattern"].to_s)
    rescue RegexpError
      errors.add(:check_config, "needs #{check_label("pattern")} to be a valid regular expression")
    end

    def validate_check_bounds(config, kind)
      min = config["min"].to_s.strip
      max = config["max"].to_s.strip
      min_label = check_label("min", kind)
      max_label = check_label("max", kind)
      if min.empty? && max.empty?
        errors.add(:check_config, "needs #{min_label} or #{max_label} filled in")
        return
      end

      min_value = CompletionKit::Checks::NumericValue.parse(min)
      max_value = CompletionKit::Checks::NumericValue.parse(max)
      if (!min.empty? && min_value.nil?) || (!max.empty? && max_value.nil?)
        errors.add(:check_config, "needs #{min_label} and #{max_label} to be numbers")
      elsif min_value && max_value && min_value > max_value
        errors.add(:check_config, "needs #{min_label} to be no more than #{max_label}")
      end
    end

    def validate_check_list_overlap(config)
      measures = CompletionKit::Checks::ListOverlap::MEASURES
      if config["score_by"].present? && !measures.include?(config["score_by"])
        errors.add(:check_config, "needs #{check_label("score_by")} to be one of #{measures.join(", ")}")
      end
      return if config["min"].to_s.strip.empty?

      threshold = CompletionKit::Checks::NumericValue.parse(config["min"])
      if threshold.nil? || threshold.negative? || threshold > 1
        errors.add(:check_config, "needs #{check_label("min", "list_overlap")} to be a number between 0 and 1")
      end
    end

    def validate_check_numeric_equals(config)
      validate_check_tolerance(config)
      return if config["compare_to"] == "expected" || config["value"].to_s.strip.empty?

      errors.add(:check_config, "needs #{check_label("value", "numeric_equals")} to be a number") if CompletionKit::Checks::NumericValue.parse(config["value"]).nil?
    end

    def validate_check_tolerance(config)
      return if config["tolerance"].to_s.strip.empty?

      tolerance = CompletionKit::Checks::NumericEquals.tolerance_value(config["tolerance"])
      if tolerance.nil? || tolerance.negative?
        errors.add(:check_config, "needs #{check_label("tolerance")} to be a number that is not negative, or a percentage like 2%")
      end
    end

    def check_label(key, kind = nil)
      "\"#{CompletionKit::Checks::Labels.field(key, kind)}\""
    end

    def set_defaults
      self.rubric_bands = self.class.default_rubric_bands if rubric_bands.blank?
    end

    def normalize_rubric_bands
      self.rubric_bands = self.class.normalize_rubric_bands(rubric_bands) if rubric_bands.present?
    end

  end
end

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
    has_many :reviews, dependent: :nullify
    has_many :dashboard_dismissals, as: :dismissable, dependent: :destroy

    METRIC_TYPES = %w[llm_judge check].freeze

    serialize :rubric_bands, coder: JSON
    serialize :check_config, coder: JSON

    validates :name, presence: true
    validates :key, tenant_scoped_uniqueness: { allow_nil: true }
    validates :metric_type, inclusion: { in: METRIC_TYPES }
    validate :validate_check_config, if: :check?
    validate :metric_type_immutable_once_in_use, on: :update

    before_validation :generate_key
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
        errors.add(:check_config, "check_kind must be one of #{CompletionKit::Checks::Registry.kinds.join(", ")}")
        return
      end

      validate_check_target(config)
      validate_check_required_keys(config, kind)
      validate_check_kind_rules(config, kind)
    end

    def validate_check_target(config)
      target = config["target"].presence || "response_text"
      unless CompletionKit::Checks::TargetResolver::TARGETS.include?(target)
        errors.add(:check_config, "target must be one of #{CompletionKit::Checks::TargetResolver::TARGETS.join(", ")}")
      end
      if target == "json_path" && config["target_path"].to_s.strip.empty?
        errors.add(:check_config, "target_path is required when target is json_path")
      end
    end

    def validate_check_required_keys(config, kind)
      CompletionKit::Checks::Registry.required_keys.fetch(kind).each do |required_key|
        if required_key == "expected"
          errors.add(:check_config, "expected is required") unless config.key?("expected")
        elsif config[required_key].to_s.strip.empty?
          errors.add(:check_config, "#{required_key} is required")
        end
      end
    end

    def validate_check_kind_rules(config, kind)
      case kind
      when "regex"
        begin
          Regexp.new(config["pattern"].to_s)
        rescue RegexpError
          errors.add(:check_config, "pattern is not a valid regular expression")
        end
      when "length_bounds"
        min = config["min"]
        max = config["max"]
        if min.nil? && max.nil?
          errors.add(:check_config, "length_bounds requires at least one of min or max")
        elsif min && max && min.to_i > max.to_i
          errors.add(:check_config, "min must be less than or equal to max")
        end
      end
    end

    def set_defaults
      self.rubric_bands = self.class.default_rubric_bands if rubric_bands.blank?
    end

    def normalize_rubric_bands
      self.rubric_bands = self.class.normalize_rubric_bands(rubric_bands) if rubric_bands.present?
    end

  end
end

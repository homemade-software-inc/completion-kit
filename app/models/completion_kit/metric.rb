module CompletionKit
  class Metric < ApplicationRecord
    DEFAULT_RUBRIC_BANDS = [
      { "stars" => 5, "description" => "Fully meets or exceeds all criteria. No meaningful issues." },
      { "stars" => 4, "description" => "Meets criteria well. Minor issues only." },
      { "stars" => 3, "description" => "Meets criteria adequately. Some room for improvement." },
      { "stars" => 2, "description" => "Partially meets criteria. Significant gaps or frequent errors." },
      { "stars" => 1, "description" => "Fails to meet the criteria. Major errors or completely off-target." }
    ].freeze

    has_many :metric_group_memberships, dependent: :destroy
    has_many :metric_groups, through: :metric_group_memberships
    has_many :reviews, dependent: :nullify

    serialize :rubric_bands, coder: JSON
    serialize :evaluation_steps, coder: JSON

    validates :name, presence: true
    validates :key, uniqueness: true, allow_nil: true

    before_validation :generate_key
    before_validation :normalize_rubric_bands
    before_validation :set_defaults

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
      band_map = Array(raw_bands).each_with_object({}) do |band, acc|
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

    private

    def generate_key
      self.key ||= name.parameterize if name.present?
    end

    def set_defaults
      self.evaluation_steps ||= []
      self.rubric_bands = self.class.default_rubric_bands if rubric_bands.blank?
    end

    def normalize_rubric_bands
      self.rubric_bands = self.class.normalize_rubric_bands(rubric_bands) if rubric_bands.present?
    end
  end
end

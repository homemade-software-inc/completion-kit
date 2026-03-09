module CompletionKit
  class Metric < ApplicationRecord
    DEFAULT_RUBRIC_BANDS = [
      {
        "range" => "1-2",
        "criteria" => "The output is irrelevant, contradicted by the input, or fails to answer the requested task in any useful way.",
        "reason" => "Use this range when the result misses the assignment so badly that a human would discard it and start over."
      },
      {
        "range" => "3-4",
        "criteria" => "The output is somewhat related but incomplete, confused, or unreliable enough that it would require major correction.",
        "reason" => "Use this range when there is a faint connection to the task, but the answer still creates substantial rework or risk."
      },
      {
        "range" => "5-6",
        "criteria" => "The output is usable in parts and generally on-topic, but it has clear gaps, weak structure, or accuracy issues that need noticeable editing.",
        "reason" => "Use this range when the answer shows partial understanding yet still falls short of a dependable production result."
      },
      {
        "range" => "7-8",
        "criteria" => "The output is strong, mostly accurate, and aligned to the task, but it misses nuance, polish, or a small requirement.",
        "reason" => "Use this range when the answer is clearly good and useful, but not the best possible version."
      },
      {
        "range" => "9-10",
        "criteria" => "The output is accurate, complete, clear, well-structured, and directly useful with little or no editing.",
        "reason" => "Use this range when the answer fully satisfies the prompt and input data with the right level of detail and judgment."
      }
    ].freeze

    has_many :metric_group_memberships, dependent: :destroy
    has_many :metric_groups, through: :metric_group_memberships
    has_many :test_result_metric_assessments, dependent: :nullify

    serialize :rubric_bands, coder: JSON

    validates :name, presence: true
    validates :rubric_text, presence: true

    before_validation :normalize_rubric_bands
    before_validation :set_defaults

    def self.default_rubric_bands
      DEFAULT_RUBRIC_BANDS.map(&:dup)
    end

    def self.default_rubric_text
      rubric_text_for(default_rubric_bands)
    end

    def self.rubric_text_for(bands)
      normalize_rubric_bands(bands).map do |band|
        <<~BAND.strip
          #{band["range"]}
          Criteria: #{band["criteria"]}
          Reasoning cue: #{band["reason"]}
        BAND
      end.join("\n\n")
    end

    def self.normalize_rubric_bands(raw_bands)
      band_map = Array(raw_bands).each_with_object({}) do |band, acc|
        next unless band.respond_to?(:to_h)

        normalized = band.to_h.stringify_keys.slice("range", "criteria", "reason")
        range = normalized["range"].to_s.strip
        next unless DEFAULT_RUBRIC_BANDS.any? { |default_band| default_band["range"] == range }

        acc[range] = {
          "range" => range,
          "criteria" => normalized["criteria"].to_s.strip,
          "reason" => normalized["reason"].to_s.strip
        }
      end

      default_rubric_bands.map do |default_band|
        band = band_map[default_band["range"]] || {}
        {
          "range" => default_band["range"],
          "criteria" => band["criteria"].presence || default_band["criteria"],
          "reason" => band["reason"].presence || default_band["reason"]
        }
      end
    end

    def rubric_bands_for_form
      self.class.normalize_rubric_bands(rubric_bands.presence || parsed_rubric_bands_from_text(rubric_text))
    end

    def display_rubric_text
      self.class.rubric_text_for(rubric_bands_for_form)
    end

    private

    def set_defaults
      self.guidance_text ||= ""
      self.rubric_bands = self.class.default_rubric_bands if rubric_bands.blank? && rubric_text.blank?
      self.rubric_text = self.class.rubric_text_for(rubric_bands) if rubric_bands.present?
      self.rubric_text ||= self.class.default_rubric_text
    end

    def normalize_rubric_bands
      self.rubric_bands = self.class.normalize_rubric_bands(rubric_bands) if rubric_bands.present?
    end

    def parsed_rubric_bands_from_text(text)
      return [] if text.blank?

      text.to_s.split(/\n{2,}/).filter_map do |chunk|
        lines = chunk.lines.map(&:strip).reject(&:blank?)
        next if lines.empty?

        range = lines.shift.to_s.strip
        default_band = self.class.default_rubric_bands.find { |band| band["range"] == range }
        next unless default_band

        criteria_line = lines.find { |line| line.start_with?("Criteria:") }
        reason_line = lines.find { |line| line.start_with?("Reasoning cue:") }

        {
          "range" => range,
          "criteria" => criteria_line.to_s.sub("Criteria:", "").strip.presence || default_band["criteria"],
          "reason" => reason_line.to_s.sub("Reasoning cue:", "").strip.presence || default_band["reason"]
        }
      end
    end
  end
end

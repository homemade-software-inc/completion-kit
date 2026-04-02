module CompletionKit
  class Prompt < ApplicationRecord
    has_many :runs, dependent: :destroy
    has_many :responses, through: :runs

    validates :name, presence: true
    validates :template, presence: true
    validates :llm_model, presence: true
    validates :family_key, presence: true
    validates :version_number, presence: true, numericality: { only_integer: true, greater_than: 0 }

    before_validation :assign_family_key, on: :create
    before_validation :assign_version_number, on: :create
    before_validation :set_defaults

    scope :current_versions, -> { where(current: true).order(created_at: :desc) }

    def self.available_models(provider: nil)
      ApiConfig.available_models(provider: provider)
    end

    def self.current_for(identifier)
      current_versions.find_by(family_key: identifier) ||
        current_versions.find_by(name: identifier) ||
        current_versions.find { |p| p.slug == identifier.to_s } ||
        raise(ActiveRecord::RecordNotFound)
    end

    def slug
      name.to_s.downcase.strip.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
    end

    def variables
      CsvProcessor.extract_variables(self)
    end

    def version_label
      "v#{version_number}"
    end

    def display_name
      "#{name} — #{version_label}"
    end

    def family_versions
      self.class.where(family_key: family_key).order(version_number: :desc, created_at: :desc)
    end

    def clone_as_new_version(overrides = {})
      self.class.create!(
        {
          name: name,
          description: description,
          template: template,
          llm_model: llm_model,
          family_key: family_key,
          version_number: next_version_number,
          current: false,
          published_at: nil
        }.merge(overrides.compact)
      )
    end

    def publish!
      transaction do
        self.class.where(family_key: family_key).where.not(id: id).update_all(current: false)
        reload
        update!(current: true, published_at: Time.current)
      end
    end

    def as_json(options = {})
      {
        id: id, name: name, description: description, template: template,
        llm_model: llm_model, family_key: family_key, version_number: version_number,
        current: current, created_at: created_at, updated_at: updated_at
      }
    end

    private

    def assign_family_key
      self.family_key ||= SecureRandom.uuid
    end

    def assign_version_number
      self.version_number ||= next_version_number
    end

    def next_version_number
      self.class.where(family_key: family_key).maximum(:version_number).to_i + 1
    end

    def set_defaults
      self.current = true if current.nil?
      self.published_at ||= Time.current if current?
    end
  end
end

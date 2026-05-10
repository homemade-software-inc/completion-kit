module CompletionKit
  class Tag < ApplicationRecord
    self.table_name = "completion_kit_tags"

    COLORS = %w[
      crimson burnt-orange amber mint deep-emerald
      electric-cyan cobalt-blue deep-indigo amethyst rose
    ].freeze

    has_many :taggings, dependent: :destroy

    before_validation :normalize_name
    before_validation :assign_color, on: :create

    validates :name, presence: true,
                     length: { maximum: 64 },
                     format: { with: /\A[\w\s\-]+\z/ },
                     tenant_scoped_uniqueness: true
    validates :color, inclusion: { in: COLORS }

    def as_json(options = {})
      {
        id: id, name: name, color: color,
        created_at: created_at, updated_at: updated_at
      }
    end

    private

    def normalize_name
      self.name = name.to_s.strip.downcase if name.present?
    end

    def assign_color
      return if color.present?
      self.color = COLORS[CompletionKit::Tag.count % COLORS.size]
    end
  end
end

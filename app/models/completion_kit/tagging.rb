module CompletionKit
  class Tagging < ApplicationRecord
    self.table_name = "completion_kit_taggings"

    belongs_to :tag, class_name: "CompletionKit::Tag"
    belongs_to :taggable, polymorphic: true

    validates :tag, presence: true
    validates :taggable, presence: true
    validates :tag_id, uniqueness: { scope: [:taggable_type, :taggable_id] }
  end
end

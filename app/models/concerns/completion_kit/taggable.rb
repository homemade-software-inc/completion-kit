module CompletionKit
  module Taggable
    extend ActiveSupport::Concern

    included do
      has_many :taggings, as: :taggable,
                          class_name: "CompletionKit::Tagging",
                          dependent: :destroy
      has_many :tags, through: :taggings, class_name: "CompletionKit::Tag"
    end

    def tag_names
      tags.pluck(:name)
    end

    def tag_names=(names)
      resolved = Array(names)
        .map { |n| n.to_s.strip.downcase }
        .reject(&:blank?)
        .uniq
      self.tags = resolved.map { |name| CompletionKit::Tag.find_or_create_by!(name: name) }
    end
  end
end

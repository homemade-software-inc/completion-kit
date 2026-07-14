module CompletionKit
  module Taggable
    extend ActiveSupport::Concern

    included do
      has_many :taggings, as: :taggable,
                          class_name: "CompletionKit::Tagging",
                          dependent: :destroy
      has_many :tags, through: :taggings, class_name: "CompletionKit::Tag"

      validate :assigned_tag_names_are_valid, if: -> { @tag_names_assigned }
      after_save :sync_assigned_tags, if: -> { @tag_names_assigned }
    end

    def tag_names
      return @assigned_tag_names if @tag_names_assigned

      tags.pluck(:name)
    end

    def tag_names=(names)
      @tag_names_assigned = true
      @assigned_tag_names = Array(names)
        .map { |n| n.to_s.strip.downcase }
        .reject(&:blank?)
        .uniq
    end

    private

    def assigned_tag_names_are_valid
      @assigned_tag_names.each do |name|
        next if CompletionKit::Tag.exists?(name: name)

        probe = CompletionKit::Tag.new(name: name)
        next if probe.valid?

        errors.add(:base, "Tag \"#{name}\" is not allowed: #{probe.errors[:name].to_sentence}")
      end
    end

    def sync_assigned_tags
      self.tags = @assigned_tag_names.map { |name| CompletionKit::Tag.find_or_create_by!(name: name) }
      @tag_names_assigned = false
      @assigned_tag_names = nil
    end
  end
end

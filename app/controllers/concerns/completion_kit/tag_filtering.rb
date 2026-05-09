module CompletionKit
  module TagFiltering
    extend ActiveSupport::Concern

    private

    def filter_tags_from_params
      names = Array(params[:tag])
        .map { |n| n.to_s.strip.downcase }
        .reject(&:blank?)
      return [] if names.empty?
      CompletionKit::Tag.where(name: names).to_a
    end
  end
end

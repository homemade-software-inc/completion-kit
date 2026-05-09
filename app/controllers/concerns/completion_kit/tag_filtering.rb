module CompletionKit
  module TagFiltering
    extend ActiveSupport::Concern

    private

    def apply_tag_filter(scope)
      @available_tags = CompletionKit::Tag.order(:name)
      @selected_tags = filter_tags_from_params
      return scope if @selected_tags.empty?
      scope.joins(:tags).where(tags: { id: @selected_tags.map(&:id) }).distinct
    end

    def filter_tags_from_params
      names = Array(params[:tag])
        .map { |n| n.to_s.strip.downcase }
        .reject(&:blank?)
      return [] if names.empty?
      CompletionKit::Tag.where(name: names).to_a
    end
  end
end

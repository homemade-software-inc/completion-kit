module CompletionKit
  class TagsController < ApplicationController
    before_action :set_tag, only: [:edit, :update, :destroy]

    def index
      @tags = Tag.order(:name)
      @tagging_counts = Tagging.group(:tag_id).count
      @tagging_by_type = Tagging.group(:tag_id, :taggable_type).count
    end

    def new
      @tag = Tag.new(color: Tag::COLORS.sample)
    end

    def edit
    end

    def create
      @tag = Tag.new(tag_params)
      if @tag.save
        redirect_to tags_path, notice: "Tag was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @tag.update(tag_params)
        redirect_to tags_path, notice: "Tag was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @tag.destroy
      redirect_to tags_path, notice: "Tag was successfully destroyed."
    end

    private

    def set_tag
      @tag = Tag.find(params[:id])
    end

    def tag_params
      params.require(:tag).permit(:name)
    end
  end
end

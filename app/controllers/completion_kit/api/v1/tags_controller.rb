module CompletionKit
  module Api
    module V1
      class TagsController < BaseController
        before_action :set_tag, only: [:show, :update, :destroy]

        def index
          render json: paginate(Tag.order(:name))
        end

        def show
          render json: @tag
        end

        def create
          tag = Tag.new(tag_params)
          if tag.save
            render json: tag, status: :created
          else
            render json: {errors: tag.errors}, status: :unprocessable_entity
          end
        end

        def update
          if @tag.update(tag_params)
            render json: @tag
          else
            render json: {errors: @tag.errors}, status: :unprocessable_entity
          end
        end

        def destroy
          @tag.destroy!
          head :no_content
        end

        private

        def set_tag
          @tag = Tag.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def tag_params
          params.permit(:name)
        end
      end
    end
  end
end

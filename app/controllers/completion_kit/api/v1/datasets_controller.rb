module CompletionKit
  module Api
    module V1
      class DatasetsController < BaseController
        before_action :set_dataset, only: [:show, :update, :destroy]

        def index
          render json: Dataset.order(created_at: :desc)
        end

        def show
          render json: @dataset
        end

        def create
          dataset = Dataset.new(dataset_params)
          if dataset.save
            render json: dataset, status: :created
          else
            render json: {errors: dataset.errors}, status: :unprocessable_entity
          end
        end

        def update
          if @dataset.update(dataset_params)
            render json: @dataset
          else
            render json: {errors: @dataset.errors}, status: :unprocessable_entity
          end
        end

        def destroy
          @dataset.destroy!
          head :no_content
        end

        private

        def set_dataset
          @dataset = Dataset.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def dataset_params
          params.permit(:name, :csv_data)
        end
      end
    end
  end
end

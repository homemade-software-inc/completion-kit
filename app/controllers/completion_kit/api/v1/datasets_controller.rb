module CompletionKit
  module Api
    module V1
      class DatasetsController < BaseController
        before_action :set_dataset, only: [:show, :update, :destroy]
        before_action :reject_oversized_upload, only: [:create, :update]

        def index
          scope = Dataset.includes(:tags)
          scope = filter_by_tags(scope)
          render json: paginate(scope.order(created_at: :desc))
        end

        def show
          render json: @dataset
        end

        def create
          dataset = Dataset.new(dataset_params)
          if dataset.save
            render json: dataset, status: :created
          else
            render_validation_errors(dataset)
          end
        end

        def update
          if @dataset.update(dataset_params)
            render json: @dataset
          else
            render_validation_errors(@dataset)
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
          permitted = params.permit(:name, :csv_data, tag_names: [])
          upload = params[:file]
          permitted[:csv_data] = upload.read.to_s.force_encoding("UTF-8") if upload.respond_to?(:read)
          permitted
        end

        def reject_oversized_upload
          upload = params[:file]
          return unless upload.respond_to?(:size) && upload.size > CompletionKit.config.max_upload_bytes

          render_error("File exceeds the #{CompletionKit.config.max_upload_bytes / (1024 * 1024)} MB upload limit", status: :payload_too_large)
        end
      end
    end
  end
end

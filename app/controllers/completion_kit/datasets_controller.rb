module CompletionKit
  class DatasetsController < ApplicationController
    before_action :set_dataset, only: [:show, :edit, :update, :destroy]

    def index
      @datasets = Dataset.order(created_at: :desc)
    end

    def show
      @runs = @dataset.runs.includes(:prompt).order(created_at: :desc)
    end

    def new
      @dataset = Dataset.new
    end

    def edit
    end

    def create
      @dataset = Dataset.new(dataset_params)

      if @dataset.save
        redirect_to datasets_path, notice: "Dataset was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @dataset.update(dataset_params)
        redirect_to @dataset, notice: "Dataset was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @dataset.destroy
      redirect_to datasets_path, notice: "Dataset was successfully destroyed."
    end

    private

    def set_dataset
      @dataset = Dataset.find(params[:id])
    end

    def dataset_params
      params.require(:dataset).permit(:name, :csv_data)
    end
  end
end

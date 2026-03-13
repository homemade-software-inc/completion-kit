module CompletionKit
  class MetricsController < ApplicationController
    before_action :set_metric, only: [:show, :edit, :update, :destroy]

    def index
      @metrics = Metric.order(:name)
    end

    def show
    end

    def new
      @metric = Metric.new
    end

    def edit
    end

    def create
      @metric = Metric.new(metric_params)

      if @metric.save
        redirect_to metric_path(@metric), notice: "Metric was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @metric.update(metric_params)
        redirect_to metric_path(@metric), notice: "Metric was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @metric.destroy
      redirect_to metrics_path, notice: "Metric was successfully destroyed."
    end

    private

    def set_metric
      @metric = Metric.find(params[:id])
    end

    def metric_params
      params.require(:metric).permit(:name, :criteria, evaluation_steps: [], rubric_bands: [:stars, :description])
    end
  end
end

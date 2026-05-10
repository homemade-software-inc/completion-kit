module CompletionKit
  class MetricGroupsController < ApplicationController
    include CompletionKit::TagFiltering
    before_action :set_metric_group, only: [:show, :edit, :update, :destroy]

    def index
      @metric_groups = apply_tag_filter(MetricGroup.includes(:metrics, :tags).order(:name))
    end

    def show
    end

    def new
      @metric_group = MetricGroup.new
      @metrics = Metric.includes(:tags).order(:name)
    end

    def edit
      @metrics = Metric.includes(:tags).order(:name)
    end

    def create
      @metric_group = MetricGroup.new(metric_group_params.except(:metric_ids))
      @metrics = Metric.includes(:tags).order(:name)

      if @metric_group.save
        @metric_group.replace_metrics!(metric_group_params[:metric_ids])
        redirect_to metric_group_path(@metric_group), notice: "Metric group was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @metrics = Metric.includes(:tags).order(:name)

      if @metric_group.update(metric_group_params.except(:metric_ids))
        @metric_group.replace_metrics!(metric_group_params[:metric_ids])
        redirect_to metric_group_path(@metric_group), notice: "Metric group was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @metric_group.destroy
      redirect_to metric_groups_path, notice: "Metric group was successfully destroyed."
    end

    private

    def set_metric_group
      @metric_group = MetricGroup.find(params[:id])
    end

    def metric_group_params
      params.require(:metric_group).permit(:name, :description, metric_ids: [], tag_names: [])
    end
  end
end

module CompletionKit
  class MetricGroupsController < ApplicationController
    before_action :set_metric_group, only: [:show, :edit, :update, :destroy]

    def index
      @metric_groups = MetricGroup.includes(:metrics).order(:name)
    end

    def show
    end

    def new
      @metric_group = MetricGroup.new
      @metrics = Metric.order(:name)
    end

    def edit
      @metrics = Metric.order(:name)
    end

    def create
      @metric_group = MetricGroup.new(metric_group_params.except(:metric_ids))
      @metrics = Metric.order(:name)

      if @metric_group.save
        replace_metric_memberships
        redirect_to metric_group_path(@metric_group), notice: "Metric group was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @metrics = Metric.order(:name)

      if @metric_group.update(metric_group_params.except(:metric_ids))
        replace_metric_memberships
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
      params.require(:metric_group).permit(:name, :description, metric_ids: [])
    end

    def replace_metric_memberships
      metric_ids = Array(metric_group_params[:metric_ids]).reject(&:blank?)
      @metric_group.metric_group_memberships.delete_all
      metric_ids.each_with_index do |metric_id, index|
        @metric_group.metric_group_memberships.create!(metric_id: metric_id, position: index + 1)
      end
    end
  end
end

module CompletionKit
  class CriteriaController < ApplicationController
    before_action :set_criteria, only: [:show, :edit, :update, :destroy]

    def index
      redirect_to metrics_path
    end

    def show
    end

    def new
      @criteria = Criteria.new
      @metrics = Metric.order(:name)
    end

    def edit
      @metrics = Metric.order(:name)
    end

    def create
      @criteria = Criteria.new(criteria_params.except(:metric_ids))
      @metrics = Metric.order(:name)

      if @criteria.save
        replace_metric_memberships
        redirect_to criterion_path(@criteria), notice: "Criteria was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @metrics = Metric.order(:name)

      if @criteria.update(criteria_params.except(:metric_ids))
        replace_metric_memberships
        redirect_to criterion_path(@criteria), notice: "Criteria was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @criteria.destroy
      redirect_to metrics_path, notice: "Criteria was successfully destroyed."
    end

    private

    def set_criteria
      @criteria = Criteria.find(params[:id])
    end

    def criteria_params
      params.require(:criteria).permit(:name, :description, metric_ids: [])
    end

    def replace_metric_memberships
      metric_ids = Array(criteria_params[:metric_ids]).reject(&:blank?)
      @criteria.criteria_memberships.delete_all
      metric_ids.each_with_index do |metric_id, index|
        @criteria.criteria_memberships.create!(metric_id: metric_id, position: index + 1)
      end
    end
  end
end

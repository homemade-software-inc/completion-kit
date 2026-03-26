class RenameCriteriaToInstructionOnMetricsAndReviews < ActiveRecord::Migration[7.0]
  def change
    rename_column :completion_kit_metrics, :criteria, :instruction
    rename_column :completion_kit_reviews, :criteria, :instruction
  end
end

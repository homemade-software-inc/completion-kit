class RestructureMetricsForStarRubric < ActiveRecord::Migration[7.1]
  def change
    change_table :completion_kit_metrics do |t|
      t.text :criteria
      t.text :evaluation_steps
      t.remove :description, type: :text
      t.remove :guidance_text, type: :text
      t.remove :rubric_text, type: :text
    end

    rename_column :completion_kit_test_result_metric_assessments, :guidance_text, :criteria
  end
end

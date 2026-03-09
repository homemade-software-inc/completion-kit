class CreateCompletionKitMetricSets < ActiveRecord::Migration[7.1]
  def change
    create_table :completion_kit_metric_sets do |t|
      t.string :name, null: false
      t.text :guidance_text
      t.text :rubric_text

      t.timestamps
    end

    add_reference :completion_kit_prompts, :metric_set, foreign_key: { to_table: :completion_kit_metric_sets }
  end
end

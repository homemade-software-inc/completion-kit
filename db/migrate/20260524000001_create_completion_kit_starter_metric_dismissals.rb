class CreateCompletionKitStarterMetricDismissals < ActiveRecord::Migration[8.1]
  def change
    create_table :completion_kit_starter_metric_dismissals do |t|
      t.string :starter_key, null: false
      t.timestamps
    end

    add_index :completion_kit_starter_metric_dismissals, :starter_key,
              unique: true,
              name: "index_ck_starter_dismissals_on_key"
  end
end

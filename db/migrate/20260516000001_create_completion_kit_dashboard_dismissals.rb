class CreateCompletionKitDashboardDismissals < ActiveRecord::Migration[8.1]
  def change
    create_table :completion_kit_dashboard_dismissals do |t|
      t.string :dismissable_type, null: false
      t.bigint :dismissable_id, null: false
      t.decimal :baseline_score, precision: 4, scale: 1
      t.timestamps
    end

    add_index :completion_kit_dashboard_dismissals,
              [:dismissable_type, :dismissable_id],
              unique: true,
              name: "index_ck_dashboard_dismissals_on_dismissable"
  end
end

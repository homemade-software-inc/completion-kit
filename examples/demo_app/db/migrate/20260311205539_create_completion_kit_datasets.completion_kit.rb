# This migration comes from completion_kit (originally 20260311000000)
class CreateCompletionKitDatasets < ActiveRecord::Migration[7.1]
  def change
    create_table :completion_kit_datasets do |t|
      t.string :name, null: false
      t.text :csv_data, null: false

      t.timestamps
    end
  end
end

class CreateRules < ActiveRecord::Migration[8.1]
  def change
    create_table :rules do |t|
      t.string :name, null: false
      t.text :description
      t.string :outcome, null: false
      t.integer :priority, null: false, default: 0
      t.boolean :active, null: false, default: true
      # Condition tree: { "combinator" => "all"|"any", "conditions" => [ {field, operator, value} | nested group ] }
      t.jsonb :conditions, null: false, default: { combinator: "all", conditions: [] }

      t.timestamps
    end
    add_index :rules, [ :active, :priority ]
  end
end

class CreateApplicants < ActiveRecord::Migration[8.1]
  def change
    create_table :applicants do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.integer :age
      t.integer :credit_score
      t.decimal :annual_income, precision: 12, scale: 2
      t.string :employment_status
      t.string :country
      t.string :status, null: false, default: "pending"
      t.references :matched_rule, foreign_key: { to_table: :rules, on_delete: :nullify }
      t.datetime :evaluated_at

      t.timestamps
    end
    add_index :applicants, :email, unique: true
    add_index :applicants, :status
  end
end

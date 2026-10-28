# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_26_055340) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "applicants", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.integer "age"
    t.integer "credit_score"
    t.decimal "annual_income", precision: 12, scale: 2
    t.string "employment_status"
    t.string "country"
    t.string "status", default: "pending", null: false
    t.bigint "matched_rule_id"
    t.datetime "evaluated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text) text_pattern_ops", name: "index_applicants_on_lower_email_prefix"
    t.index "lower((name)::text) text_pattern_ops", name: "index_applicants_on_lower_name_prefix"
    t.index ["email"], name: "index_applicants_on_email", unique: true
    t.index ["email"], name: "index_applicants_on_email_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["matched_rule_id"], name: "index_applicants_on_matched_rule_id"
    t.index ["name"], name: "index_applicants_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["status"], name: "index_applicants_on_status"
  end

  create_table "idempotency_keys", force: :cascade do |t|
    t.string "key", null: false
    t.string "request_method", null: false
    t.string "request_path", null: false
    t.string "request_fingerprint", null: false
    t.datetime "locked_at"
    t.integer "response_status"
    t.text "response_body"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_idempotency_keys_on_created_at"
    t.index ["key", "request_method", "request_path"], name: "index_idempotency_keys_uniqueness", unique: true
  end

  create_table "rules", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "outcome", null: false
    t.integer "priority", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.jsonb "conditions", default: {"combinator" => "all", "conditions" => []}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "priority"], name: "index_rules_on_active_and_priority"
  end

  add_foreign_key "applicants", "rules", column: "matched_rule_id", on_delete: :nullify
end

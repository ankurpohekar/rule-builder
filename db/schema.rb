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

ActiveRecord::Schema[8.1].define(version: 2026_10_30_042333) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "vector"

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
    t.index ["created_at", "id"], name: "index_applicants_on_created_at_and_id"
    t.index ["email"], name: "index_applicants_on_email", unique: true
    t.index ["email"], name: "index_applicants_on_email_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["matched_rule_id"], name: "index_applicants_on_matched_rule_id"
    t.index ["name"], name: "index_applicants_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["status", "created_at", "id"], name: "index_applicants_on_status_and_created_at_and_id"
  end

  create_table "faq_entries", force: :cascade do |t|
    t.string "key", null: false
    t.string "section_title", null: false
    t.text "question", null: false
    t.text "answer", null: false
    t.string "content_digest", null: false
    t.vector "embedding", limit: 384
    t.virtual "searchable", type: :tsvector, as: "(setweight(to_tsvector('english'::regconfig, question), 'A'::\"char\") || setweight(to_tsvector('english'::regconfig, answer), 'B'::\"char\"))", stored: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_faq_entries_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["key"], name: "index_faq_entries_on_key", unique: true
    t.index ["searchable"], name: "index_faq_entries_on_searchable", using: :gin
  end

  create_table "faq_questions", force: :cascade do |t|
    t.text "question", null: false
    t.text "answer"
    t.boolean "answered", default: false, null: false
    t.jsonb "retrieved", default: [], null: false
    t.string "sources", default: [], null: false, array: true
    t.float "top_similarity"
    t.integer "feedback"
    t.integer "duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["answered"], name: "index_faq_questions_on_answered"
    t.index ["created_at"], name: "index_faq_questions_on_created_at"
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

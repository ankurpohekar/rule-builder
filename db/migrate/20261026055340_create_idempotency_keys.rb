# Stores the outcome of requests sent with an Idempotency-Key header, so a retry of the
# same request gets the original response instead of running the action again.
class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :idempotency_keys do |t|
      t.string :key, null: false
      t.string :request_method, null: false
      t.string :request_path, null: false
      t.string :request_fingerprint, null: false # SHA-256 of the request body
      t.datetime :locked_at                      # set while the original request is running
      t.integer :response_status
      t.text :response_body
      t.datetime :completed_at

      t.timestamps
    end
    # The unique index is what makes claiming a key atomic under concurrent retries.
    add_index :idempotency_keys, %i[key request_method request_path], unique: true, name: "index_idempotency_keys_uniqueness"
    add_index :idempotency_keys, :created_at
  end
end

# Substring search (ILIKE '%term%') on name and email can't use B-tree indexes.
# Trigram GIN indexes can: Postgres splits values into 3-character pieces and looks up
# the pieces of the search term. Built concurrently so writes aren't blocked on large tables.
class AddTrigramSearchIndexesToApplicants < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    enable_extension "pg_trgm"

    add_index :applicants, :name, using: :gin, opclass: :gin_trgm_ops,
      name: "index_applicants_on_name_trgm", algorithm: :concurrently
    add_index :applicants, :email, using: :gin, opclass: :gin_trgm_ops,
      name: "index_applicants_on_email_trgm", algorithm: :concurrently
  end
end

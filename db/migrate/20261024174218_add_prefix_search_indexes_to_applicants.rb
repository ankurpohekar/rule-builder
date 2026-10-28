# Trigram indexes only help terms of 3+ characters, so 1-2 character searches match
# prefixes instead. With a non-C collation, LIKE 'ab%' can only use a B-tree built with
# text_pattern_ops; indexing lower(...) makes the match case-insensitive.
class AddPrefixSearchIndexesToApplicants < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :applicants, "lower(name) text_pattern_ops",
      name: "index_applicants_on_lower_name_prefix", algorithm: :concurrently
    add_index :applicants, "lower(email) text_pattern_ops",
      name: "index_applicants_on_lower_email_prefix", algorithm: :concurrently
  end
end

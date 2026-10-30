# Indexes for keyset pagination of the applicant list: ORDER BY created_at DESC, id DESC
# WHERE (created_at, id) < (cursor). Postgres reads these backwards for the DESC order, so
# every page is an index range scan, however deep, instead of an OFFSET that reads and
# discards all earlier rows.
#
# Built CONCURRENTLY so a large table keeps accepting writes while the index builds.
class AddPaginationIndexesToApplicants < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :applicants, %i[created_at id], algorithm: :concurrently
    add_index :applicants, %i[status created_at id], algorithm: :concurrently
    # The (status, created_at, id) index also serves plain status lookups.
    remove_index :applicants, :status, algorithm: :concurrently
  end
end

class AddLastSeenToNode < ActiveRecord::Migration
  def change
    add_column :nodes, :seen_at, :datetime
  end
end


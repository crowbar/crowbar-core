class AddLastSeenToNode < ActiveRecord::Migration
  def change
    add_column :nodes, :last_seen, :datetime
  end
end


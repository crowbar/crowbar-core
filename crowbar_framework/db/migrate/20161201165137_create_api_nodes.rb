class CreateApiNodes < ActiveRecord::Migration
  def change
    create_table :nodes do |t|
      t.string :name
      t.string :alias
      t.datetime :last_seen
    end
  end
end

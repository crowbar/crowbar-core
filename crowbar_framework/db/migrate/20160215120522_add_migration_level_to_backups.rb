class AddMigrationLevelToBackups < ActiveRecord::Migration
  def change
    add_column :backups, :migration_level, :integer, limit: 8, default: 20151222144602
  end
end

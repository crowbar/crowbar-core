class ChangeBackupVersionType < ActiveRecord::Migration
  def up
    change_column :backups, :version, :string
  end

  def down
    change_column :backups, :version, :float
  end
end

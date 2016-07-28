class ChangeBackupVersionType < ActiveRecord::Migration
  def up
    change_column :backups, :version, :string
  end

  def down
    type = if Rails.configuration.database_configuration[Rails.env]["adapter"] == "postgresql"
      "float USING version::double precision"
    else
      :float
    end
    change_column :backups, :version, type
  end
end

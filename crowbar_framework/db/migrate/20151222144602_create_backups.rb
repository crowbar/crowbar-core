class CreateBackups < ActiveRecord::Migration
  def change
    create_table :backups do |t|
      t.string :name
      t.float :version
      t.integer :size

      t.timestamps null: false
    end
  end
end

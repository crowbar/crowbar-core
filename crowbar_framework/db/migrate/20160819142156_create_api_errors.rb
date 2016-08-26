class CreateApiErrors < ActiveRecord::Migration
  def change
    create_table :errors do |t|
      t.string :error
      t.text :message
      t.integer :code
      t.string :caller
      t.text :backtrace

      t.timestamps null: false
    end
  end
end

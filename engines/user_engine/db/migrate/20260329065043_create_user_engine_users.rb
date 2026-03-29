class CreateUserEngineUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :user_engine_users do |t|
      t.string :name
      t.string :email

      t.timestamps
    end
    add_index :user_engine_users, :email, unique: true
  end
end

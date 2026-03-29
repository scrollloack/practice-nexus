class CreateEmailEngineProcessedEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :email_engine_processed_events do |t|
      t.string :event_id, null: false
      t.string :topic, null: false
      t.datetime :processed_at, null: false

      t.timestamps
    end
    add_index :email_engine_processed_events, [ :event_id, :topic ], unique: true
  end
end

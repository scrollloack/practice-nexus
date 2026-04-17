class CreateAuditEngineAuditLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :audit_engine_audit_logs do |t|
      t.integer :user_id, null: false
      t.string :action, null: false
      t.text :changed_fields
      t.datetime :occurred_at, null: false
      t.string :event_id, null: false
      t.string :topic, null: false

      t.timestamps
    end

    # Unique constraint → idempotency guard built into the table itself
    # No separate ProcessedEvent table needed — the audit log IS the idempotency record
    add_index :audit_engine_audit_logs, [ :event_id, :topic ], unique: true
    add_index :audit_engine_audit_logs, :user_id
  end
end

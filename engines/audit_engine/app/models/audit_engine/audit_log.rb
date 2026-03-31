module AuditEngine
  class AuditLog < ApplicationRecord
    validates :user_id, presence: true
    validates :action, presence: true, inclusion: { in: %w[created updated] }
    validates :occurred_at, presence: true
    validates :event_id, presence: true
    validates :topic, presence: true
  end
end

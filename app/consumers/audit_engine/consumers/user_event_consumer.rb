module AuditEngine
  module Consumers
    class UserEventConsumer < Karafka::BaseConsumer
      def consume
        messages.each do |message|
          process_event(message)
        end
      end

      private

      def process_event(message)
        payload = message.payload.with_indifferent_access
        payload = JSON.parse(payload, symbolize_names: true) if payload.is_a?(String)

        Rails.logger.info "[AuditEngine] Received #{payload[:event]} for user_id:#{payload[:user_id]}"

        # Idempotency check — the unique index on [event_id, topic] will also enforce this
        # at the DB level, but we check first to avoid unnecessary DB writes

        nil if AuditEngine::AuditLog.exists?(event_id: message.offset, topic: message.topic)

        action = case payload[:event]
                 when 'user.created' then 'created'
                 when 'user.updated' then 'updated'
                 else
                   Rails.logger.warn "[AuditEngine] Unknown event type: #{payload[:event]}"
                   return
                 end

        AuditEngine::AuditLog.create!(
          user_id: payload[:user_id],
          action: action,
          changed_fields: payload[:changed_fields]&.to_json,
          occurred_at: payload[:occurred_at],
          event_id: message.offset,
          topic: message.topic
        )

        Rails.logger.info "[AuditEngine] Audit log written: user_id:#{payload[:user_id]} action=#{action}"
      end
    end
  end
end

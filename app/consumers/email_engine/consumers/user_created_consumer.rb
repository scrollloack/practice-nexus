module EmailEngine
  module Consumers
    class UserCreatedConsumer < Karafka::BaseConsumer
      def consume
        # `messages` is a batch of events - Karfaka delivers them in batches
        messages.each do |message|
          process_event(message)
        end
      end

      private

      def process_event(message)
        payload = JSON.parse(message.payload, symbolize_names: true)

        Rails.logger.info "[EmailEngine] Received user.created for user_id=#{user.id}"

        # Idempotency check - don't send duplicate welcome emails
        nil if ProcessedEvent.exists?(event_id: message.offset, topic: message.topic)

        # Business logic: send a welcome email to the newly created user
        EmailEngine::UserMailer.welcome(
          user_id: payload[:user_id],
          name: payload[:name],
          email: payload[:email],
        )

        # Record that we've processed this event
        ProcessedEvent.create!(
          event_id: message.offset,
          topic: message.topic,
          process_at: Time.current
        )
      end
    end
  end
end

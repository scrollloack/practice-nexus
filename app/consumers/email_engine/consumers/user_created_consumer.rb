module EmailEngine
  module Consumers
    class UserCreatedConsumer < Karafka::BaseConsumer
      def consume
        # `messages` is a batch of events — Karafka delivers them in batches
        messages.each do |message|
          process_event(message)
        end
        # messages.each do |message|
        #   # payload is already deserialized by Karafka
        #   payload = message.payload
        #   payload = JSON.parse(payload, symbolize_names: true) if payload.is_a?(String)
        #   puts "[EmailEngine] ✅ Consumed: #{payload.inspect}"
        #   Rails.logger.info "[EmailEngine] ✅ Consumed: #{payload.inspect}"
        # end
      end

      private

      def process_event(message)
        payload = message.payload.with_indifferent_access
        payload = JSON.parse(payload, symbolize_names: true) if payload.is_a?(String)


        Rails.logger.info "[EmailEngine] Received user.created for user_id=#{payload[:user_id]}"

        # Idempotency check — don't send duplicate welcome emails (see Step 8.5)
        return if EmailEngine::ProcessedEvent.exists?(event_id: message.offset, topic: message.topic)

        # Business logic: send a welcome email to the newly created user
        EmailEngine::UserMailer.welcome(
          user_id: payload[:user_id],
          name:    payload[:name],
          email:   payload[:email]
        ).deliver_now

        # Record that we've processed this event
        EmailEngine::ProcessedEvent.create!(
          event_id:    message.offset,
          topic:       message.topic,
          processed_at: Time.current
        )
      end
    end
  end
end

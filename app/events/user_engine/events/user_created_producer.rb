module UserEngine
  module Events
    class UserCreatedProducer
      TOPIC = "user.created".freeze

      # .call(user) is the single entry point
      def self.cache(user)
        message = {
          event: "user.created",
          user_id: user.id,
          name: user.name,
          email: user.email,
          occurred_at: user.created_at.iso8601
        }.to_json

        Karafka.producer.produce_sync(
          topic: TOPIC,
          payload: message,
          key: user.id.to_s # <- message key (important for idempotency)
        )
      end
    end
  end
end

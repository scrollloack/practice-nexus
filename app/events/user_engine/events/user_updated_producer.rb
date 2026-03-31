module UserEngine
  module Events
    class UserUpdatedProducer
      TOPIC = 'user.updated'.freeze

      # .call(user, changed_fields) is the single entry point
      # changed_fields: hash of { field_name => new_value } for
      # fields that were actually updated
      def self.call(user, changed_fields)
        message = {
          event: 'user.updated',
          user_id: user.id,
          name: user.name,
          email: user.email,
          changed_fields: changed_fields,
          occurred_at: user.updated_at.iso8601
        }.to_json

        Karafka.producer.produce_sync(
          topic: TOPIC,
          payload: message,
          key: user.id.to_s # same key as user.created -> same partition -> ordered events per user
        )
      end
    end
  end
end

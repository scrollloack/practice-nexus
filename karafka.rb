# frozen_string_literal: true

class KarafkaApp < Karafka::App
  setup do |config|
    kafka_config = {}
    kafka_config[:'bootstrap.servers'] = ENV.fetch('KAFKA_BROKER', 'kafka:9092')
    kafka_config[:'auto.offset.reset'] = 'earliest'
    config.kafka = kafka_config
    config.client_id = 'practice_nexus'
  end

  routes.draw do
    consumer_group :email_service do
      topic 'user.created' do
        consumer EmailEngine::Consumers::UserCreatedConsumer
      end
    end

    consumer_group :audit_service do
      topic 'user.created' do
        consumer AuditEngine::Consumers::UserEventConsumer
      end

      topic 'user.updated' do
        consumer AuditEngine::Consumers::UserEventConsumer
      end
    end
  end
end

Karafka.monitor.subscribe('error.occurred') do |event|
  puts "KARAFKA ERROR: #{event[:error].class}: #{event[:error].message}"
  puts event[:error].backtrace.join("\n")
end

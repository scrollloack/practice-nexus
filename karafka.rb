# karafka.rb
class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = {
      "bootstrap.servers": ENV.fetch("KAFKA_BROKER", "localhost:9092")
    }
    config.client_id = "nexus"
    config.consumer_persistence = true
  end

  routes.draw do
    # EmailEngine subscribes to the user.created topic
    topic "user.created" do
      consumer EmailEngine::Consumers::UserCreatedConsumer
    end
  end
end

module UserEngine
  module Types
    class UserType < GraphQL::Schema::Object
      description "A registered user in the system"

      # Each field corresponds to an attribute on UserEngine::User
      field :id,         Integer, null: false
      field :name,       String,  null: false
      field :email,      String,  null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end

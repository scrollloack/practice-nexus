module UserEngine
  module Resolvers
    class UserResolver < GraphQL::Schema::Resolver
      description "Fetch a single user by ID"
      type Types::UserType, null: true

      argument :id, Integer, required: true

      def resolve(id:)
        UserEngine::User.find_by(id: id)
      end
    end
  end
end

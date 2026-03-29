module UserEngine
  module Resolvers
    class UsersResolver < GraphQL::Schema::Resolver
      description "Fetch all users"
      type [ Types::UserType ], null: false

      def resolve
        UserEngine::User.all
      end
    end
  end
end

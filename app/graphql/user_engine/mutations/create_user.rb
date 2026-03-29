module UserEngine
  module Mutations
    class CreateUser < GraphQL::Schema::Mutation
      description "Create a new user"

      # What goes IN  (the input type we defined above)
      # app/graphql/user_engine/types/create_user_input.rb
      argument :input, Types::CreateUserInput, required: true

      # What comes OUT (the type that will be returned)
      field :user, Types::UserType, null: true
      field :errors, [ String ], null: true

      def resolve(input:)
        user = UserEngine::User.new(
          name: input[:name],
          email: input[:email]
        )

        if user.save
          # After successful save → publish Kafka event (covered in Section 8)

          UserEngine::Events::UserCreatedProducer.call(user)

          { user: user, errors: [] }
        else
          { user: nil, errors: user.errors.full_messages }
        end
      end
    end
  end
end

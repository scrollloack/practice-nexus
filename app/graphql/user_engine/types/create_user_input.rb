module UserEngine
  module Types
    class CreateUserInput < GraphQL::Schema::InputObject
      description "Input fields required to create a new user"

      argument :name,  String, required: true,  description: "Full name of the user"
      argument :email, String, required: true,  description: "Unique email address"
    end
  end
end

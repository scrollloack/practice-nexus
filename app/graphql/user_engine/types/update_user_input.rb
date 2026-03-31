module UserEngine
  module Types
    class UpdateUserInput < GraphQL::Schema::InputObject
      description 'Input fields for updating an existing user. All data fields are optional - only send what should change.'

      argument :id, Integer, required: true, description: 'ID of the user to update.'
      argument :name, String, required: false, description: 'New full name (omit to leave unchanged)'
      argument :email, String, required: false, description: 'New email address (omit to leave unchanged)'
    end
  end
end

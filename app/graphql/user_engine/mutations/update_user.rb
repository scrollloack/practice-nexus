# frozen_string_literal: true

module UserEngine
  module Mutations
    class UpdateUser < GraphQL::Schema::Mutation
      description "Update an existing user's name and/or email"

      argument :input, Types::UpdateUserInput, required: true

      field :user, Types::UserType, null: true
      field :errors, [String], null: false

      def resolve(input:)
        user = UserEngine::User.find_by(id: input[:id])

        return { user: nil, errors: ['User not found'] } if user.nil?

        # Build only the attributes the client actually sent (reject nil values)
        attrs = {}
        attrs[:name] = input[:name] unless input[:name].nil?
        attrs[:email] = input[:email] unless input[:email].nil?

        return { user: user, errors: ['No fields provided to update'] } if attrs.empty?

        if user.update(attrs)
          # user.previous_changes returns { "field" => [old_value, new_value] }
          # We only want the new values for the changed fields
          changed = user.previous_changes
                        .except('updated_at')
                        .transform_values(&:last)

          UserEngine::Events::UserUpdatedProducer.call(user, changed)

          { user: user, errors: [] }
        else
          { user: nil, errors: user.errors.full_messages }
        end
      end
    end
  end
end

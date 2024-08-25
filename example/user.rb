class User < ActiveRecord::Base
  include ActionAPI::Model

  # scopes
  scope :with_first_name, lambda {|val|
    where(first_name: first_name)
  }

  # Create or update user
  #
  # @param [Hash] options
  # @option opts [String] :first_name First name
  # @option opts [String] :last_name Last name
  # ...
  #
  def update_as_action!(opts)
    # request context has scope, includes, etc
    request_context = opts[:request_context]
    actor = opts[:request_actor] # or request_context.actor
    new_record = self.new_record?

    # initialize new record
    if new_record
      # set fields
    end

    # authorization
    policy = Pundit.policy(actor, self)
    policy.authorize! :create?

    # update fields
    # ...

    success = self.save
    if success && new_record
      # trigger background jobs
      # ...
    end

    # return results (ActionAPI handles serialization)
    return {success: true, data: self}
  end

  def delete_as_action!(opts)
    actor = opts[:request_context].actor
    # authorization
    policy = Pundit.policy(actor, self)
    policy.authorize! :destroy?
    self.destroy
    return {success: true, data: self}
  end

  # background jobs

  def validate_phone_numbers!
    # try to make background jobs idempotent

  end

  # class method examples

  def self.index_as_action!(opts)
    # This method will be automatically included by ActionAPI::Model
    request_context = opts[:request_context]
    # build ScopeResponder
    # NOTE: Scope responder uses `id`, `scope`, `limit`, `include`, `sort` etc.
    # params to automatically fetch records from database. You can
    # extend the scope responder to customize
    #
    res = User::ScopeResponder.new(request_context).result
    # {success: success, data: [User]}
    return res
  end

  # scope responding

  class ScopeResponder < ActionAPI::ActiveRecordScopeResponder
    def accessible_scope
      UserPolicy::Scope.new(request_context.actor, User).resolve
    end
    def allowed_scope_names
      # could be dependent on request actor
      [:with_first_name, :with_last_name, :with_organization_id]
    end
    def allowed_includes
      [:addresses]
    end
    def enhance_items(items)
      # can further augment each item after it's retrieved depending
      # on RequestContext
    end
  end

end

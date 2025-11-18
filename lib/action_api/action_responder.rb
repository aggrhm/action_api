module ActionAPI

  ##
  # An ActionResponder gives a ruby object or service the ability
  # to facilitate transactional business logic on behalf of an actor
  # in a standardized and trackable way. It's called "ActionResponder"
  # because it allows an actor to perform an action with a given set
  # of parameters.
  #
  class ActionResponder
    include ActionAPI::Documentation

    attr_reader :resource_class, :action_context

    def self.inherited(subclass)
      subclass.set_resource_class(subclass.module_parent)
    end

    def self.set_resource_class(cls)
      @resource_class = cls
    end

    def self.find_for_class(cls)
      if defined?(cls::ActionResponder)
        return cls::ActionResponder
      elsif defined?(cls.class::ActionResponder)
        return cls.class::ActionResponder
      else
        return nil
      end
    end

    def initialize(resource_class: nil)
      @resource_class = resource_class || self.class.resource_class
    end

    def perform(action, opts)
      res = nil
      inst = opts[:instance]
      begin
        res = execute_action(action, opts)
        # prepare response
        if !res.is_a?(RequestResult)
          res = RequestResult.new(data: res)
        end
      rescue => ex
        # prepare error
        ActionAPI.log_exception(ex)
        res = RequestResult.new(errors: [ex])
        res.data = inst if inst
      end
      return res
    end

    def perform!(action, opts)
      res = perform(action, opts)
      res.raise_if_error!
      return res
    end

    def execute_action(action, opts)
      @action_context = {}
      action = action.to_s
      @action_context[:action] = action.to_sym
      inst = opts[:instance]

      # prepare request
      @action_context[:instance] = inst
      @action_context[:request_context] = req = (opts[:request_context] || RequestContext.new)
      req.actor = opts[:actor] if opts.key?(:actor)
      req.params = opts[:params] if opts.key?(:params)
      process_request_context(req)

      # prepare instance
      arity = self.method(action.to_sym).arity
      action_args = []
      if arity == 1
        if inst.blank?
          inst = @action_context[:instance] = load_instance()
          raise ActionAPI::Errors::ResourceNotFoundError if inst.blank?
        end
        action_args = [inst]
      elsif arity == 0
        raise ArgumentError, "Action '#{action}' expected no instance argument but one was given" if inst
      elsif arity > 1
        raise ArgumentError, "Action '#{action}' expects an improper number of arguments"
      end

      # perform the request
      res = self.public_send action, *action_args

      return res
    end

    def process_request_context(request_context)
      responder_class = self.class
      rc = request_context
      action = action_context[:action].to_s
      # action params
      doc = ActionAPI.find_api_docs(resource_class: responder_class, attributes: {kind: :action, name: action}).first
      if doc
        rc.processed_params = ActionAPI.process_params_with_api_doc(rc.params, doc)
      end
    end


    def list
      resource_class.scope_responder(request_context).result
    end

    def create
      m = resource_class.new
      perform :update, instance: m, request_context: request_context
    end

    def retrieve(m)
      m
    end

    def request_context
      action_context[:request_context]
    end

    def actor
      request_context.actor
    end

    def params
      request_context.params
    end

    def load_instance
      resource_class.scope_responder(request_context).item
    end

    def actor_policy(model)
      Pundit.policy!(actor, model)
    end

    def authorized_transaction!(model, action: nil)
      # authorize via pundit
      action ||= action_context[:action]
      query = "#{action.to_s}?".to_sym
      Pundit.policy!(actor, model).authorize!(query)

      # perform transaction
      model.class.transaction do
        yield
      end
    end

  end

end

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
        if !res.is_a?(Hash) || (res.keys.collect(&:to_s) & ["success", "data", "error"]).empty?
          res = {success: true, data: res}
        end
      rescue => ex
        # prepare error
        ActionAPI.log_exception(ex)
        res = {success: false, error: ex}
        res[:data] = inst if inst
      end
      if res[:success] != true && opts[:raise_error] == true
        raise res[:error] || (res[:errors] || []).first
      end
      return res
    end

    def execute_action(action, opts)
      @action_context = {}
      action = action.to_s
      # find action responder
      @action_context[:action] = action.to_sym
      inst = opts[:instance]
      receiver = opts[:instance] || resource_class
      res = nil
      rsp_cls = self.class
      rsp = self
      raise "No action responder was found for #{rsp_cls.to_s}" if rsp_cls.nil?

      # prepare request
      @action_context[:instance] = inst
      @action_context[:request_context] = req = (opts[:request_context] || RequestContext.new)
      req.actor = opts[:actor] if opts.key?(:actor)
      req.params = opts[:params] if opts.key?(:params)

      # process request
      process_request_context(req, responder: rsp, action: action)

      # perform the request
      rsp_args = inst ? [inst] : []

      arity = rsp.method(action.to_sym).arity
      if arity < rsp_args.length
        raise ArgumentError, 'Expected no instance argument but one was given'
      elsif arity > rsp_args.length
        raise ArgumentError, 'Expected instance argument, but none was given'
      end

      res = rsp.public_send action, *rsp_args

      return res
    end

    def process_request_context(request_context, responder:, action:)
      if responder.class == Class
        responder_class = responder
      else
        responder_class = responder.class
      end
      rc = request_context
      # action params
      doc = ActionAPI.find_api_docs(resource_class: responder_class, attributes: {action: action}).first
      if doc
        rc.processed_params = rc.processed_params.merge(ActionAPI.process_params_with_api_doc(rc.params, doc))
      end
    end


    def index
      resource_class.scope_responder(request_context).result
    end

    def create
      m = resource_class.new
      perform :update, instance: m, request_context: request_context
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
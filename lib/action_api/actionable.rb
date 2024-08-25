module ActionAPI

  module Actionable

    def self.included(base)
      base.send :extend, ClassMethods
      base.include ActionAPI::Documentation
    end

    module ClassMethods

      def perform_action(action, opts)
        # find action responder or create anonymous one
        rsp_cls = ActionResponder.find_for_class(self) || ActionResponder
        rsp = rsp_cls.new(resource_class: self)
        rsp.perform(action, opts)
      end

    end

    def perform_action(action, opts)
      return self.class.perform_action(action, opts.merge(instance: self))
    end

  end

  class ActionBuilder

    def initialize(resource_name, action_name, &block)
      ctx = "action:#{resource_name}##{action_name}"
      @doc_builder = APIDocBuilder.new(ctx)
      @scope = :instance
      res = instance_eval(&block)
      if @performer.nil?
        @performer = res
      end
    end

    def class_action
      @scope = :class
    end

    def perform(&block)
      @performer = block
    end

    def configuration
      {
        scope: @scope,
        performer: @performer,
        doc: @doc_builder.doc
      }
    end

    def method_missing(name, *args)
      @doc_builder.send(name, *args)
    end

  end

end
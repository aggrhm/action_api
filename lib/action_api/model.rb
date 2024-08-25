module ActionAPI

  module Model

    def self.included(base)
      base.send :extend, ClassMethods
      base.include ActionAPI::Actionable
    end

    module ClassMethods

      def scope_responder(ctx, opts={})
        if defined?(self::ScopeResponder)
          cls = self::ScopeResponder
        else
          cls = ActionAPI::ActiveRecordScopeResponder
        end
        cls.new(resource_class: self, request_context: ctx)
      end

      def scope_names
        return @scope_names ||= []
      end

      def scope(name, body, &block)
        ret = super(name, body, &block)
        scope_names << name
        return ret
      end

      def serializer_class
        # Check to see if a serializer is defined in the superclass
        model_class = self
        while model_class != Object && model_class.present?
          serializer = "#{model_class.name}Serializer".constantize rescue nil
          break if serializer.present?
          model_class = model_class.superclass
        end

        return serializer if serializer

        raise ArgumentError, "Could not find serializer for `#{self.name}`. If using a serializer other than `#{self.name}Serializer`, specify using `serializer_class` defined on #{self}"
      end

      def parse_request_context(opts)
        ActionAPI.parse_request_context(opts)
      end

    end

    # INSTANCE METHODS

    def parse_request_context(opts)
      ActionAPI.parse_request_context(opts)
    end

    def update_fields_from(data, fields, options={})
      fields.each do |field|
        if data.key?(field)
          val = data[field]
          if options[:strip] != false
            val = val.strip if val.respond_to?(:strip)
          end
          self.send "#{field.to_s}=", val
        end
      end
    end

    def error_message
      self.error_messages.first
    end

    def error_messages
      self.errors.messages.values.flatten
    end

    def has_present_association?(assoc)
      self.association(assoc).loaded? && self.send(assoc).present?
    end

    # NOTE: This method is for data meant to be serialized, and may be overridden
    # to add additional default fields. It is not named `meta` because meta may
    # already be defined on the resource, and may have data meant to be persisted
    # (a column meant for persisting should ideally be named `cached_meta` so that
    # meta is not so ambiguous).
    def resource_meta
      @resource_meta ||= {}
    end

    def resource_links
      @resource_links ||= []
    end

    def resource_errors
      self.errors.try(:to_json_api) || self.errors
    end

  end

end

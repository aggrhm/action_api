module ActionAPI

  module Documentation

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods

      def api_doc(attrs={}, &block)
        # NOTE: User should be able to subclass the default
        # APIDocBuilder class and set it as a default for
        # this library to be used here.
        builder = APIDocBuilder.new(self, attrs, &block)
        doc = builder.doc
        ActionAPI.docs[doc.context] = doc
        api_docs << doc
        return doc
      end

      def publish_action(action, &block)
        api_doc({kind: :action, name: action, is_public: true}, &block)
      end

      def publish_filter(filter, &block)
        api_doc({kind: :filter, name: filter, is_public: true}, &block)
      end

      def publish_filters(*filters, &block)
        filters.each {|filter| publish_filter(filter, &block)}
      end

      def publish_sort(sort, &block)
        api_doc({kind: :sort, name: sort, is_public: true}, &block)
      end

      def publish_sorts(*sorts, &block)
        sorts.each {|sort| publish_sort(sort, &block)}
      end

      def publish_scope(scope, &block)
        Rails.logger.info("The `publish_scope` method is deprecated.")
      end

      def api_docs
        @api_docs ||= []
      end

    end

  end

  class APIDoc

    attr_reader :attributes, :index

    def initialize
      @attributes = {}
      @index = {}
    end

    def context
      ret = attributes[:context]
      ret ||= "#{resource_class.to_s}.#{kind.to_s}.#{name.to_s}"
      return ret
    end

    def set(key, val)
      attributes[key.to_sym] = val
    end

    def append(key, val)
      key = key.to_sym
      attributes[key] ||= []
      attributes[key] << val
      index[key] ||= {}
      index[key][val[:name].to_s] = val
    end

    def method_missing(name, *args)
      return attributes[name.to_sym]
    end

  end

  class APIDocBuilder

    attr_reader :doc

    def initialize(resource_class, attrs={}, &block)
      @doc = APIDoc.new
      @doc.attributes.merge!(attrs)
      @doc.set(:resource_class, resource_class)
      @doc.set(:params, [])
      instance_eval(&block) if block
      raise "Context not specified" if @doc.context.nil?
    end

    def param(name, type, desc=nil, opts={})
      if desc.is_a?(Hash)
        opts = desc
        desc = nil
      end
      doc.append :params, {name: name, type: type, description: desc, meta: opts}
    end

    def method_missing(name, *args)
      doc.set(name, args.length == 1 ? args.first : args)
    end

  end

end

module ActionAPI

  module Documentation

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods

      def api_doc(attrs={}, &block)
        builder = APIDocBuilder.new(self, attrs, &block)
        doc = builder.doc
        ActionAPI.docs[doc.context] = doc
        api_docs << doc
        return doc
      end

      def publish_action(action, &block)
        api_doc({action: action, is_public: true}, &block)
      end

      def publish_scope(scope, &block)
        api_doc({scope: scope, is_public: true}, &block)
      end

      def publish_scopes(*scopes, &block)
        scopes.each {|scope| publish_scope(scope, &block)}
      end

      def publish_sort(sort, &block)
        api_doc({sort: sort, is_public: true}, &block)
      end

      def publish_sorts(*sorts, &block)
        sorts.each {|sort| publish_sort(sort, &block)}
      end

      def api_docs
        @api_docs ||= []
      end

    end

  end

  class APIDoc

    attr_reader :attributes

    def initialize
      @attributes = {}
    end

    def context
      ret = attributes[:context]
      if ret.nil?
        if attributes[:action]
          ret = "#{resource_class.to_s}.action.#{action}"
        elsif attributes[:scope]
          ret = "#{resource_class.to_s}.scope.#{scope}"
        elsif attributes[:sort]
          ret = "#{resource_class.to_s}.sort.#{sort}"
        end
      end
      return ret
    end

    def set(key, val)
      attributes[key.to_sym] = val
    end

    def append(key, val)
      attributes[key.to_sym] ||= []
      attributes[key.to_sym] << val
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
      doc.append(:params, {name: name, type: type, description: desc, meta: opts})
    end

    def nested_param(parent, name, type, desc=nil, opts={})
      doc.append(:nested_params, {parent: parent, name: name, type: type, description: desc, meta: opts})
    end

    def method_missing(name, *args)
      doc.set(name, args.length == 1 ? args.first : args)
    end

  end

end

module ActionAPI

  class ScopeResponder
    include ActionAPI::Documentation

    attr_reader :resource_class, :request_context, :options

    def initialize(resource_class:, request_context:, options: {}, &block)
      @options = options
      @resource_class = resource_class
      @request_context = request_context
      prepare
      block.call(self) if block
    end

    def prepare

    end

    def accessible_scope
      options[:accessible_scope]
    end

    def default_selectors
      {}
    end

    def query_selectors
      default_selectors.merge(request_context.selectors)
    end

    def query_sort
      request_context.sort
    end

    def default_relation
      accessible_scope
    end

    def actor
      request_context.actor
    end

    def includes
      return request_context.includes
    end

    def build_database_relation(base=nil)
      process_request_context
      sort = query_sort
      base ||= default_relation
      base = base.preload(includes) if includes.present?
      base = query_selectors.reduce(base) do |chain, (scope_name, scope_args)|
        if scope_args.present?
          if scope_args.is_a?(Hash)
            chain.public_send(scope_name, **scope_args.symbolize_keys)
          else
            scope_args_array = [scope_args].flatten
            chain.public_send(scope_name, *scope_args_array)
          end
        else
          chain.public_send(scope_name)
        end
      end

      # add sort
      if sort.present?
        base = base.public_send(sort.to_sym)
      end
      return base
    end

    def build_database_result
      ctx = request_context
      params = request_context.params
      ret = { success: true, error: nil, data: nil, meta: {} }

      if params.key?(:id)
        rel = build_database_relation(accessible_scope)
        ret[:data] = rel.find(params[:id])
      else
        rel = build_database_relation
        # TODO: Possibly replace with pagy?
        data = rel.limit(pagination[:limit]).offset(pagination[:offset]).to_a
        count = rel.reselect(:id).reorder(nil).distinct.count(:all)

        pages_count = (count / pagination[:limit].to_f).ceil
        if params.key?(:first)
          data = data.first
        elsif params.key?(:last)
          data = data.last
        end

        if pagination[:all] && count > max_limit
          ret[:error] = ActionAPI::InvalidParamError.new(message: "Requested all records, but there are more than max_limit: #{max_limit}.")
        end
        ret[:data] = data
        ret[:meta] = {count: count, pages_count: pages_count, page: ctx.page}
      end

      if ret[:data].nil?
        ret[:success] = false
        ret[:error] ||= ActionAPI::ResourceNotFoundError.new
      end

      enhance_items(ret[:data].is_a?(Array) ? ret[:data] : [ret[:data]])
      return ret
    end

    def item(opts={})
      res = result(opts)
      res[:data]
    end

    def items(opts={})
      res = result(opts)
      res[:data]
    end

    def enhance_items(items)
      # use enhances here
    end

    def count
      res = result(opts)
      res[:count]
    end

    def pagination
      @pagination ||= begin
        ctx = request_context
        limit = ctx.limit || 100
        page = ctx.page || 1
        all = false
        offset = 0

        raise if limit > max_limit

        if limit == 0
          limit = max_limit
          all = true
        end

        if page && limit
          offset = (page - 1) * limit
        end

        { limit: limit, offset: offset, all: all }
      end
    end

    def build_result
      build_database_result
    end

    def result(opts={})
      if @result.nil? || opts[:reload]
        @result = build_result
      end
      return @result
    end

    def process_request_context
      # filters
      rc = request_context
      if rc.sort.present?
        doc = ActionAPI.find_api_docs(resource_class: self.class, attributes: {sort: rc.sort, is_public: true}).first
        raise "Sort #{rc.sort} could not be found" if doc.nil?
        rc.sort = rc.sort.to_sym
      end

      rc.filters.each do |name, args|
        # find doc for scope
        doc = ActionAPI.find_api_docs(resource_class: self.class, attributes: {scope: name, is_public: true}).first
        raise "Filter #{name} could not be found" if doc.nil?

        # convert args to hash
        hargs = args
        if !args.is_a?(Hash)
          if doc.params.length > 0
            fpn = doc.params.first[:name]
            hargs = {fpn.to_s => args}
          else
            hargs = {}
          end
        end
        hargs = hargs.with_indifferent_access

        # set default args
        doc.params.each do |param|
          if !hargs.has_key?(param[:name]) && param[:meta].has_key?(:default)
            hargs[param[:name]] = param[:meta][:default]
          end
        end

        phargs = hargs.merge(ActionAPI.process_params_with_api_doc(hargs.with_indifferent_access, doc))
        pass_value = doc.params.length == 1 && (doc.params.first[:meta] || {})[:with_key] == false
        rc.filters[name] = pass_value ? phargs.values.first : phargs
      end
    end

    def max_limit
      10000
    end

  end

  class ActiveRecordScopeResponder < ScopeResponder

    def model
      resource_class
    end

    def accessible_scope
      raise 'You must define a scope responder with `accessible_scope`'
    end

    def allowed_query_sort_fields
      nil
    end

    def allowed_polymorphic_ar_includes
      {}
    end

    def includes
      @_includes ||= ar_includes
    end

    def ar_includes
      incls = request_context.includes || []
      ret = {}
      incls.each do |ref|
        ch = ret
        cls = resource_class
        plm = allowed_polymorphic_ar_includes
        ref.split(".").each do |rp|
          plm = plm[rp] if plm
          if cls
            rel = cls.reflections[rp]
            break if rel.nil?
            if rel.polymorphic?
              cls = nil
            else
              cls = rel.klass
            end
          else
            break if plm.nil?
          end
          ch[rp] ||= {}
          ch = ch[rp]
        end
      end
      return ret
    end

  end

end

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

    def query_aggregations
      request_context.param(:aggregations, default: {})
    end

    def default_relation
      accessible_scope
    end

    def actor
      request_context.actor
    end

    def params
      request_context.params
    end

    def includes
      return request_context.includes
    end

    def build_result
      initialize_result

      # build data and pagination
      prepare_data_result

      # build aggregations
      prepare_aggregations_result if query_aggregations.present?

      # allow additional result enhancements
      enhance_result

      return @current_result
    end

    def initialize_result
      @current_result = ActionAPI::RequestResult.new(meta: {warnings: []})
    end

    def prepare_data_result

    end

    def prepare_aggregations_result

    end

    def enhance_result

    end

    def item(opts={})
      res = result(opts)
      res[:data]
    end

    def items(opts={})
      res = result(opts)
      res[:data]
    end

    def count(opts={})
      res = result(opts)
      res[:meta][:page][:count]
    end

    def pagination
      @pagination ||= begin
        ctx = request_context
        page = ctx.page || {}
        limit = page["size"].blank? ? 100 : page["size"].to_i
        pnum = page["number"].blank? ? 1 : page["number"].to_i
        all = false
        offset = 0

        raise if limit > max_limit

        if limit == -1
          limit = max_limit
          all = true
        end

        if pnum && limit
          offset = (pnum - 1) * limit
        end
        { page_number: pnum, limit: limit, offset: offset, all: all }
      end
    end

    def sorting
      @sorting ||= begin
        sort = request_context.sort
        if sort.blank?
          return {sort_name: nil}
        end

        sort_name = sort; dir = :asc
        if sort[0] == "-"
          sort_name = sort[1..-1]
          dir = :desc
        end
        sort_scope = "order_by_#{sort_name}".to_sym

        {sort_name: sort_name, direction: dir, sort_scope: sort_scope}
      end
    end

    def result(opts={})
      if @result.nil? || opts[:reload]
        @result = build_result
      end
      return @result
    end

    def process_request_context
      rc = request_context

      # sorting
      if sorting[:sort_name].present?
        doc = ActionAPI.find_api_docs(resource_class: self.class, attributes: {sort: sorting[:sort_name], is_public: true}).first
        raise "Sort #{sorting[:sort_name]} could not be found" if doc.nil?
      end

      # filters
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

    def build_database_relation(base=nil)
      process_request_context
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
      if sorting[:sort_name].present?
        begin
          base = base.public_send(sorting[:sort_scope], direction: sorting[:direction])
        rescue ArgumentError
          raise APIError, "Sort '#{sorting[:sort_name]}' does not properly accept direction."
        end
      end
      return base
    end

    def accessible_database_relation
      @accessible_database_relation ||= build_database_relation(accessible_scope)
    end

    def database_relation
      @database_relation ||= build_database_relation
    end

    def prepare_data_result
      if params.key?(:id)
        rel = accessible_database_relation
        @current_result.data = rel.find(params[:id])
      else
        rel = database_relation

        # fetch data
        if pagination[:limit] == 0
          data = []
        else
          data = rel.limit(pagination[:limit]).offset(pagination[:offset]).to_a
          if params.key?(:first)
            data = data.first
          elsif params.key?(:last)
            data = data.last
          end
        end

        @current_result.data = data

        # add pagination
        prepare_pagination_result
      end

      if @current_result.data.nil?
        raise ActionAPI::ResourceNotFoundError.new
      end

      return rel
    end

    def prepare_pagination_result
      count = database_relation.reselect(:id).reorder(nil).distinct.count(:all)

      pages_count = (count / pagination[:limit].to_f).ceil
      pnum = pagination[:page_number]
      poffset = pagination[:offset]
      if pagination[:all] && count > max_limit
        @current_result.meta[:warnings] << { message: "Requested all records, but there are more than max_limit: #{max_limit}." }
      end
      @current_result.meta[:page] = { records_count: count, pages_count: pages_count, number: pnum, size: pagination[:limit], offset: pagination[:offset] }
    end

  end

end
module ActionAPI

  class RequestContext

    attr_accessor :actor, :params, :args, :processed_params, :validated_params, :meta

    def initialize(opts={})
      self.meta = opts[:meta] || {}
      if opts[:params]
        self.params = (opts[:params] || {})
        self.actor = opts[:actor]
      else
        self.params = opts
        self.actor = opts[:request_actor] || opts[:actor]
      end
    end

    # NOTE: This should be dynamically computed by instance methods instead of stored
    def parse_params
      if params[:filters]
        params[:filters] = ActionAPI.parse_opts(params[:filters])
      end
      params[:limit] = params[:limit].to_i if params[:limit]
      params[:page] = params[:page].to_i if params[:page]
      params[:fields] = ActionAPI.parse_opts(params[:fields]) if params[:fields]
      params[:fields] ||= {}
      params[:include] = ActionAPI.parse_opts(params[:include]) if params[:include]
      params[:include] ||= []
      params[:enhance] = ActionAPI.parse_opts(params[:enhance]) if params[:enhance]
      params[:sort] = ActionAPI.parse_opts(params[:sort]) if params[:sort]
    rescue => ex
      ActionAPI.log_exception(ex)
    end

    def params=(val)
      @params = val.try(:with_indifferent_access)
      @processed_params = @params.dup
      @validated_params = nil
      parse_params
      return @params
    end

    def processed_params=(val)
      @processed_params = val.try(:with_indifferent_access)
    end

    def validated_params=(val)
      @validated_params = val.try(:with_indifferent_access)
    end

    def params
      @processed_params || @params
    end

    def original_params
      @params
    end

    def selector_names
      selectors.keys
    end

    def scope
      filters
    end

    def selectors
      filters
    end

    def filters
      params[:filters] || {}
    end

    def limit
      params[:limit]
    end

    def page
      params[:page] || 1
    end

    def fields
      params[:fields]
    end

    def includes
      params[:include]
    end

    def enhances
      params[:enhances]
    end

    def sort
      params[:sort]
    end

    def sort=(val)
      params[:sort] = val
    end

    def selectors=(val)
      params[:filters] = val
    end

    def includes=(val)
      params[:include] = val
    end

    def enhances=(val)
      params[:enhances] = val
    end

    # use this when need a subcontext hash
    def to_action_params
      ret = {}
      ret[:actor] = actor
      ret[:params] = params
      ret[:request_context] = self
      return ret
    end

  end


end

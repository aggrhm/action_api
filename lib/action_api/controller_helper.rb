module ActionAPI

  module ControllerHelper

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods

      def action_api_options
        return {
          default_serializer_name: @default_serializer_name,
          engine_path: @engine_path
        }
      end
      def default_serializer_name(val)
        @default_serializer_name = val
      end
      def engine_path(val)
        @engine_path = val
      end

    end

    def request_context
      @request_context ||= begin
        actor   = self.respond_to?(:current_user, true)   ? current_user   : nil
        actor ||= self.respond_to?(:current_member, true) ? current_member : nil
        RequestContext.new(params: params.to_unsafe_hash, actor: actor)
      end
    end

    def model_class
      @model_class ||= request_endpoint[:class_name].constantize
    end

    def request_endpoint
      return @endpoint if !@endpoint.nil?
      # determine mount
      mp = params[:qs_api_mount_path]
      @mount = ActionAPI::Endpoints.mounts[mp]
      # determine endpoint
      method = request.method.downcase.to_sym
      path = request.path
      eng_path = self.class.action_api_options[:engine_path]
      if eng_path.present?
        path = path[eng_path.length..-1]
      end
      #puts path
      @endpoint = @mount.endpoints[ [method, path] ]
    end

    def prepare_request_context

    end

    def handle_api_request
      begin
        # call endpoint method
        prepare_request_context
        res = call_endpoint_action(request_endpoint)
      rescue => ex
        ActionAPI.log_exception(ex)
        res = {success: false, error: ex}
      end
      render_result(res)
    end

    def call_endpoint_action(endpoint)
      r_ctx = request_context

      if endpoint[:class_action].present?
        Rails.logger.debug "Endpoint: #{endpoint[:class_name]}.#{endpoint[:class_action]}"
        rcv = model_class
        rcv_action = endpoint[:class_action]
      else
        # load model
        load_model_instance
        if (endpoint[:instantiate_if_nil] == true) && @model.nil?
          @model = model_class.new
        end
        Rails.logger.debug "Endpoint: #{endpoint[:class_name]}.#{endpoint[:action]}"
        rcv = @model
        rcv_action = endpoint[:action]
      end

      if rcv.respond_to?(:perform_action)
        res = rcv.perform_action rcv_action, request_context: r_ctx
      else
        res = rcv.send rcv_action, **r_ctx.to_action_params
      end
      return res
    end

    def model_scope_responder
      @model_scope_responder ||= begin
        if defined?(model_class::ScopeResponder)
          cls = model_class::ScopeResponder
        else
          cls = ActionAPI::ActiveRecordScopeResponder
        end
        cls.new(resource_class: model_class, request_context: request_context)
      end
    end

    def load_model_instance
      if params[:id].present?
        @model = model_scope_responder.item
        raise ActionAPI::Errors::ResourceNotFoundError if @model.nil?
      end
      return @model
    end

    # Render result to JSON using the serializers
    def render_result(res)
      rc = request_context

      # find serializer for data
      def_ser_name = self.class.action_api_options[:default_serializer_name]
      ser_cls = ActionAPI.serializer_class_for(res[:data]) || def_ser_name.constantize
      ser_opts = {
        params: {request_context: rc}
      }
      # Don't add fields/include to default_serialization
      if ser_cls.to_s != def_ser_name
        ser_opts[:fields]  = rc.fields   if rc.fields.present?
        ser_opts[:include] = rc.includes if rc.includes.present?
      end
      ser_opts[:meta] = res[:meta] if res[:meta].present?
      ActionAPI.config.transform_serializer_options.call({data: res[:data], options: ser_opts, serializer_class: ser_cls, request_context: rc})
      json = ser_cls.new(res[:data], ser_opts).serializable_hash

      # errors
      errs = [res[:errors], res[:error]].flatten(1).compact
      err_status = nil
      if res[:success] == false || errs.length
        jerrs = json["errors"] = []
        jerr = {}
        errs.each do |err|
          jerr = {}
          if err.is_a?(String)
            jerr = {detail: err}
          elsif err.is_a?(Hash)
            jerr = {detail: err[:message] || err[:detail], code: err[:code], status: err[:status].try(:to_s), meta: err[:meta] || {}}
          elsif err.is_a?(ActionAPI::APIError)
            jerr = err.to_json_api
          else
            jerr = ActionAPI.config.transform_error.call(err)
          end
          jerr[:code] ||= "APIError"
          jerr[:status] ||= "500"
          err_status ||= jerr[:status]    # set response status
          jerrs << jerr
        end
      end

      if res[:success]
        status = "200"
      else
        status = err_status || "500"
      end

      render :json => ActiveSupport::JSON.encode(json), :status => status
    end

  end

end

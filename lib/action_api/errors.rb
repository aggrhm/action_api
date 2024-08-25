module ActionAPI

  module Errors

    class APIError < StandardError
        attr_reader :resource
        def initialize(opts={})
          super
          if opts.is_a?(String)
            @message = opts
            @human_message = nil
            @resp = {}
          else
            opts ||= {}
            @resp = opts
            @message = opts[:message]
            @human_message = opts[:human_message]
            @code = opts[:code]
            @status = opts[:status]
            @meta = opts[:meta]
            @resource = opts[:resource]
          end
        end
        def message
          @message ||= "An error occurred at the server."
        end
        def human_message
          @human_message ||= message
        end
        def code
          @code ||= "APIError"
        end
        def status
          @status ||= 500
        end
        def meta
          @meta ||= {}
        end
        def to_json_api
          return {
            detail: message,
            code: code,
            status: status,
            meta: meta
          }
        end
    end
    class ResourceNotFoundError < APIError
      def message
        @message ||= "The resource you are trying to load or update could not be found."
      end
      def status
        @status ||= 404
      end
      def code
        "ResourceNotFoundError"
      end
    end
    class InvalidParamError < APIError
      def message
        @message ||= "A parameter you specified was invalid."
      end
      def code
        "InvalidParamError"
      end
    end

  end

end

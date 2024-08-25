require "action_api/version"
require "action_api/endpoints"
require "action_api/controller_helper"
require "action_api/serializer_helper"
require "action_api/request_context"
require "action_api/helpers"
require "action_api/documentation"
require "action_api/scope_responder"
require "action_api/action_responder"
require "action_api/actionable"
require "action_api/model"
require "action_api/errors"
require "action_api/active_model"

module ActionAPI
  # Your code goes here...
  extend Helpers
  include Errors

  class Configuration

    def initialize
      self.default_model_index_action = :index
      self.default_model_save_action = :update
      self.default_model_delete_action = :delete
      self.transform_error = lambda {|err|
        return {detail: err.message, code: err.class.name.split("::").last, status: "500"}
      }
      self.transform_serializer_options = lambda {|topts|
      }
    end

    attr_accessor :default_model_index_method
    attr_accessor :default_model_save_method
    attr_accessor :default_model_delete_method

    attr_accessor :transform_error, :transform_serializer_options
  end

  def self.config
    @config ||= ActionAPI::Configuration.new
  end

  def self.serializers
    @serializers ||= {}
  end

  def self.docs
    @docs ||= {}
  end

  def self.find_api_docs(resource_class:, attributes:)
    return [] if !resource_class.respond_to?(:api_docs)
    resource_class.api_docs.select {|doc|
      attributes.reduce(true) do |memo, (k, v)|
        memo && doc.attributes[k].to_s == v.to_s
      end
    }
  end

end


if defined?(Rails::Railtie)
  class ActionDispatch::Routing::Mapper

    def mount_api_endpoints(mount_path, opts={}, &block)
      raise ArgumentError, 'Must supply a block to mount_api_endpoints' unless block
      mount = nil

      mount = ActionAPI::Endpoints.configure(mount_path, opts, &block)

      mount.endpoints.each do |key, val|
        method, path = key
        match path, controller: mount.controller, action: "handle_api_request", via: method, defaults: {qs_api_mount_path: mount.full_path}
      end
    end

  end

end

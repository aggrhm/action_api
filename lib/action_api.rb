require "action_api/version"
require "action_api/endpoints"
require "action_api/controller_helper"
require "action_api/serializer_helper"
require "action_api/request_context"
require "action_api/request_result"
require "action_api/helpers"
require "action_api/documentation"
require "action_api/scope_responder"
require "action_api/action_responder"
require "action_api/actionable"
require "action_api/model"
require "action_api/errors"
require "action_api/active_model"
require "action_api/automation/base_reactor"
require "action_api/automation/event"
require "action_api/automation/eventable"
require "action_api/automation/reactor_service"

module ActionAPI
  # Your code goes here...
  extend Helpers
  include Errors

  class Configuration

    def initialize
      self.default_model_list_action = :list
      self.default_model_create_action = :create
      self.default_model_retrieve_action = :retrieve
      self.default_model_update_action = :update
      self.default_model_delete_action = :delete

      self.default_event_domain = nil

      self.transform_error = lambda {|err|
        return {detail: err.message, code: err.class.name.split("::").last, status: "500"}
      }
      self.transform_serializer_options = lambda {|topts|
      }

      self.log_exception = lambda do |ex, opts|
        Rails.logger.error(ex.full_message)
      end
      self.enqueue_job = lambda do |job|
        raise "Job processing not configured."
      end
    end

    attr_accessor :default_model_list_action
    attr_accessor :default_model_retrieve_action
    attr_accessor :default_model_create_action
    attr_accessor :default_model_update_action
    attr_accessor :default_model_delete_action

    attr_accessor :default_event_domain

    attr_accessor :transform_error, :transform_serializer_options
    attr_accessor :log_exception
    attr_accessor :enqueue_job
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

  def self.perform_job(job)
    action = job['action']
    context = action.split(".").first
    case context
    when 'reactor_service'
      Automation::ReactorService.shared.perform_job(job)
    else
      raise "Unknown job context: #{action}"
    end
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

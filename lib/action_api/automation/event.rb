module ActionAPI
  module Automation

    class Event

      attr_accessor :domain, :object_type, :object_id, :verb, :actor_type, :actor_id, :time, :meta, :action
      attr_accessor :reaction_enabled, :reaction

      # Helper method for creating event from a model.
      # Should raise exception inside of transaction
      def self.publish_for_model!(model,
        actor:,
        verb:,
        domain: nil,
        time: nil,
        meta: nil,
        react: true)

        domain ||= ActionAPI.config.default_event_domain

        action = generate_action(domain: domain, object: model, verb: verb)

        time ||= Time.now

        ev = Event.new(
          time:       time,
          domain:     domain,
          verb:       verb,
          action:     action,
          actor:      actor,
          object:     model,
          meta:    meta
        )

        ev.reaction_enabled = react

        # just trigger reaction
        raise "Event is invalid" if !ev.valid?

        ev.perform_sync_reactions

        ev.enqueue_async_reactions
      end

      def self.from_hash(val)
        self.new(
          domain: val['domain'],
          object_type: val['object_type'],
          object_id: val['object_id'],
          actor_type: val['actor_type'],
          actor_id: val['actor_id'],
          verb: val['verb'],
          action: val['action'],
          time: val['time'],
          meta: val['meta']
        )
      end

      def initialize(domain:, verb:, action:, time:, object_type: nil, object_id: nil, object: nil, actor_type: nil, actor_id: nil, actor: nil, meta: {})
        if object
          @object = object
          object_type = object.class.name
          object_id = object.id
        end
        if actor
          @actor = actor
          actor_type = actor.class.name
          actor_id = actor.id
        end
        self.domain = domain
        self.verb = verb
        self.action = action
        self.time = time.is_a?(String) ? Time.parse(time) : time
        self.object_type = object_type
        self.object_id = object_id
        self.actor_type = actor_type
        self.actor_id = actor_id
        self.meta = meta
      end

      def object
        @object ||= object_type.constantize.find(object_id)
      end

      def actor
        @actor ||= actor_type.constantize.find(actor_id)
      end

      def to_websocket
        payload = self.attributes
          .to_h
          .except('id', 'verb', 'domain')
        payload['time'] = payload['time'].iso8601
        payload
      end

      def perform_sync_reactions
        return unless reaction_enabled
        ReactorService.shared.react_sync(self)
      end

      def enqueue_async_reactions
        return unless reaction_enabled
        return unless has_async_reactions?
        if ActiveRecord::Base.connection.transaction_open?
          object.async_event_queue << self
        else
          ReactorService.shared.react_async(self)
        end
      end

      def has_async_reactions?
        ReactorService.shared.subscriptions_for_event(self, mode: :async).present?
      end

      def prepare_fields
        self.time ||= Time.now
      end

      def valid?
        return false if object_type.blank? || object_id.blank? || actor_type.blank? || actor_id.blank? || verb.blank? || action.blank? || time.blank? || domain.blank?
        return true
      end

      class << self
      private

        def generate_action(domain:, object:, verb:)
          context_str = object.class.name.gsub("::", "").underscore
          "#{domain}:#{context_str}##{verb}"
        end

      end

    end

  end
end
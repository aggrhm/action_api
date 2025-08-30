module ActionAPI
  module Automation

    class ReactorService

      def self.shared
        @shared ||= self.new
      end

      def initialize
        setup
      end

      def react_sync(event)
        handle_event(event, mode: :sync)
      end

      def react_async(event)
        async_subs = subscriptions_for_event(event, mode: :async)
        sub_queue_groups = async_subs.group_by{ |s| s[:queue] || 'within_5_hours' }
        sub_queue_groups.each do |queue, subs|
          sub_names = subs.collect{ |s| s[:name] }
          job_options = {
            'action' => 'reactor_service.handle_event_async',
            'queue' => queue,
            'sub_names' => sub_names,
            'event' => event.as_json
          }
          ActionAPI.config.enqueue_job.call(job_options)
        end
      end

      def perform_job(job)
        queue = job["queue"]
        ev = Event.from_hash(job["event"])
        self.handle_event(ev, mode: :async, queue: queue)
      end

      def handle_event(event, mode:, queue: nil)
        subs = subscriptions_for_event(event, mode: mode, queue: queue)

        return if subs.empty?
        event.reaction = { mode: mode }
        subs.each do |s|
          begin
            s[:reactor].send(s[:method], event)
          rescue => ex
            raise if mode == :sync # raise for sync exceptions
            SmartAPI.log_exception(ex)
          end
        end
      end

      def subscriptions_index
        @subscriptions_index
      end

      def add_subscription(s)
        mode = s[:mode].to_sym
        action = s[:action].to_s

        subscriptions_index[mode][action] ||= []
        subscriptions_index[mode][action] << s
      end

      def subscriptions_for_event(event, mode:, queue: nil)
        action = event.action
        subs = subscriptions_index[mode.to_sym][action] || []
        subs += (subscriptions_index[mode.to_sym]['all'] || [])

        # select subs with queue
        if mode == :async && queue.present?
          subs = subs.select{ |s| s[:queue] == queue }
        end

        # select subs with conditionals
        subs = subs.select{ |s| s[:if].nil? || s[:if].call(event) }
        return subs
      end

      def register_reactor(reactor)
        reactor = reactor.new if reactor.is_a?(Class)
        subs = reactor.subscriptions
        subs.each do |s|
          add_subscription(s)
        end
      end

      def register_reactors(*reactors)
        reactors.each {|r| register_reactor(r) }
      end

      def setup
        @subscriptions_index = {
          sync: {},
          async: {}
        }
      end

    end

  end
end
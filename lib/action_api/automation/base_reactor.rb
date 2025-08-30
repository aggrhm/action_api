module ActionAPI

  module Automation

    class BaseReactor

      attr_reader :subscriptions

      def self.subscribe_to(actions, method, mode: :async, queue: nil, **opts)
        actions = [actions] if !actions.is_a?(Array)
        queue = 'default' if queue.nil? && mode == :async
        rname = self.name.split("::").last
        actions.each do |action|
          subscriptions << { action: action, method: method, mode: mode, queue: queue, name: "#{rname}.#{method}" }.merge(opts)
        end
      end

      def self.subscriptions
        @subscriptions ||= []
      end

      def initialize
        # iterate class subs on init, cloning, checking for method, and setting reactor
        @subscriptions = []
        self.class.subscriptions.each do |s|
          ns = s.dup.merge(reactor: self)
          # validate sub
          raise "Subscription '#{ns[:name]}' method not found" if !ns[:reactor].respond_to?(ns[:method])
          @subscriptions << ns
        end
      end

    end

  end

end
module ActionAPI
  module Automation

    module Eventable
      extend ActiveSupport::Concern
      included do

        after_commit :flush_async_event_queue
        after_rollback :clear_async_event_queue

      end

      def save_with_event!(opts)
        new_record = new_record?
        save!

        # Try to assume verb
        if opts[:verb].nil?
          opts[:verb] = new_record ? 'created' : 'updated'
        end

        # Try to assume time
        if opts[:time].nil?
          if opts[:verb] == 'created' && self.respond_to?(:created_at)
            opts[:time] = self.created_at
          end
        end

        opts[:meta] = self.event_meta

        Event.publish_for_model!(self, **opts)
      end

      ##
      # Override this method to provide additional meta
      #
      def event_meta
      end

      def async_event_queue
        @async_event_queue ||= []
      end

      def clear_async_event_queue
        @async_event_queue = []
      end

      def flush_async_event_queue
        async_event_queue.each do |ev|
          ReactorService.shared.react_async(ev)
        end

      ensure
        clear_async_event_queue
      end


    end

  end
end
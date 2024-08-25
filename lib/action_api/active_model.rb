module ActionAPI

  module ActiveModel

    module ErrorsHelper

      def full_details
        ret = {}
        details.each do |key, dets|
          kfds = []
          dets.each_with_index do |det, idx|
            kfd = {}.merge(det)
            msg = self.messages[key][idx]
            kfd[:message] ||= msg.to_s
            kfd[:full_message] ||= begin
              m = kfd[:message]
              flcap = m[0] && m[0] == m[0].upcase
              flcap ? m : full_message(key, m)
            end
            kfds << kfd
          end
          ret[key] = kfds
        end
        return ret
      end
  
      def to_json_api
        ret = {}
        full_details.each do |key, dets|
          eobjs = []
          dets.each do |det|
            eobj = {}
            eobj[:status] = 400
            ferr = det[:full_error]
            jerr = det[:json_error]
            if ferr
              if ferr.respond_to?(:to_json_api)
                eobj = eobj.merge(ferr.to_json_api)
              else
                eobj = ActionAPI.config.transform_error.call(ferr)
              end
            elsif jerr
              eobj = jerr
            else
              eobj[:code] = "RecordInvalid"
              eobj[:detail] = det[:full_message]
              eobj[:meta] = {
                validation_error: det[:error],
                validation_options: {} # options for validation later
              }
            end
            # add attribute to meta
            eobj[:meta] ||= {}
            eobj[:meta][:attribute] = key
            eobjs << eobj
          end
          ret[key] = eobjs
        end
        return ret.values.flatten
      end
  
      def add_full_error(attribute, full_error, options = {})
        options[:full_error] = full_error
        add(attribute, full_error.message, options)
      end
  
      def add_json_error(attribute, json_error, options = {})
        options[:json_error] = json_error
        add(attribute, json_error[:detail], options)
      end
  
      def proper_full_messages
        msgs = full_details.values.flatten.collect{|d| d[:full_message]}.uniq
      end

    end

  end

end
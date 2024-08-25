module ActionAPI

  module Helpers

    def parse_bool(val)
      return nil if (val != false && val.blank?)
      if [true, "true", 1, "1", "t"].include?(val)
        return true
      else
        return false
      end
    end

    def parse_integer(val)
      return nil if val.blank?
      return val.to_i
    end

    def parse_float(val)
      return nil if val.blank?
      return val.to_f
    end

    def parse_string(val)
      return nil if val.nil?
      return val.to_s
    end

    def parse_time(val)
      return nil if val.blank?
      if val.is_a?(String)
        return Time.parse(val)
      elsif val.is_a?(Numeric)
        return Time.at(val)
      else
        return val
      end
    end

    def parse_date(val)
      return nil if val.blank?
      if val.is_a?(String)
        return Date.parse(val)
      else
        return val
      end
    end

    def parse_opts(opts)
      return nil if opts.nil?
      new_opts = opts
      if opts.is_a?(String) && !opts.blank?
        begin
          new_opts = JSON.parse(opts)
        rescue => ex
          new_opts = opts
        end
      end
      if new_opts.is_a?(Hash)
        return new_opts.with_indifferent_access
      else
        return new_opts
      end
    end

    def parse_data(opts)
      self.parse_opts(opts)
    end

    def parse_value_with_type(val, type)
      ret = case type
      when :integer
        parse_integer(val)
      when :string
        parse_string(val)
      when :date
        parse_date(val)
      when :float
        parse_float(val)
      when :time, :datetime
        parse_time(val)
      when :bool, :boolean
        parse_bool(val)
      else
        val
      end
      return ret
    end

    def process_params_with_api_doc(params, doc)
      ret = {}
      doc = doc.is_a?(String) ? ActionAPI.docs[doc] : doc
      raise "Could not properly parse parameters, context not found." if doc.nil?

      # transform each param
      doc.params.each do |param|
        begin
          pt = param[:type]
          pn = param[:name]
          # skip if not present
          next if !params.key?(pn)
          val = params[pn]
          if param[:array]
            if !val.is_a?(Array)
              val = [val].compact
            end
            nval = val.collect {|v| parse_value_with_type(v, pt)}
          else
            nval = parse_value_with_type(val, pt)
          end
          ret[pn] = nval
        rescue => ex
          ActionAPI.log_exception(ex, notify: false)
          raise ActionAPI::APIError.new("Param '#{pn}' could not be parsed.")
        end
      end
      return ret
    end

    ##
    # Parses opts to guarantee request context returned
    #
    def parse_request_context(opts)
      if opts.is_a?(ActionAPI::RequestContext)
        return [opts, opts.params]
      elsif opts.is_a?(Hash)
        if opts[:request_context]
          return [opts[:request_context], opts]
        else
          rc = ActionAPI::RequestContext.new(opts)
          return [rc, rc.params]
        end
      else
        rc = ActionAPI::RequestContext.new({})
        return [rc, rc.params]
      end
    end

    def log_exception(ex, opts={})
      if Rails.env.test?
        puts ex.full_message
      else
        Rails.logger.info ex.full_message
      end
      if opts[:notify] != false
        if defined?(ExceptionNotifier)
          ExceptionNotifier.notify_exception(ex, opts)
        end
        if defined?(Appsignal)
          Appsignal.set_error(ex)
        end
        if defined?(Datadog) && defined?(Datadog::Tracing)
          span = Datadog::Tracing.active_span
          span.set_error(ex) unless span.nil?
        end
      end
    rescue => ex
      Rails.logger.info ex.message
      Rails.logger.info ex.backtrace.join("\n\t")
    end

    def bool_tree(arr)
      ret = {}
      return nil if arr.nil?
      return arr if arr.is_a?(Hash)
      arr.each do |val|
        if val.is_a?(Hash)
          val.each do |hk, hv|
            ret[hk] = self.bool_tree(hv)
          end
        else
          ret[val] = {}
        end
      end
      return ret
    end

    def bool_tree_intersection(tree1, tree2)
      ret = {}
      return nil if tree1.nil? || tree2.nil?
      tree1.each do |k, v|
        t2v = tree2[k]
        if t2v.nil?
          next
        elsif !v.empty?
          ret[k] = self.bool_tree_intersection(v, t2v)
        else
          ret[k] = {}
        end
      end
      return ret
    end

    def bool_tree_to_array(tree)
      ret = []
      tree.each do |k, v|
        if !v.empty?
          ret << {k => self.bool_tree_to_array(v)}
        else
          ret << k
        end
      end
      return ret
    end

    def serializer_class_for(data)
      # get data object
      if data.is_a?(Array)
        obj = data.first
      else
        obj = data
      end

      obj_cls = obj.class
      obj_cls = obj if obj_cls.name == "Class"
      if obj.nil?
        return nil
      elsif obj_cls.respond_to?(:serializer_class)
        serializer_name = obj_cls.serializer_class.name
      else
        ocn = obj_cls.name.to_s
        pot_ser_names = [(ocn.classify + 'Serializer')]
        if ocn.include?("::")
          pot_ser_names << (ocn.gsub("::", "") + 'Serializer')
          pot_ser_names << (ocn.split("::").last + 'Serializer')
        end
        pot_ser_names.each do |pot_ser_name|
          if !pot_ser_name.safe_constantize.nil?
            serializer_name = pot_ser_name
            break
          end
        end
      end
      #puts "Serializer used: " + serializer_name
      return serializer_name.try(:constantize)
    end

  end

end

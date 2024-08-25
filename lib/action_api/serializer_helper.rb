module ActionAPI

  module SerializerHelper

    def self.included(base)
      base.extend ClassMethods
      class << base
        attr_accessor :resolved_presets_cache
      end
      ActionAPI.serializers[base.to_s.to_sym] = base
      # meta
      base.meta do |model|
        ret = {}
        if model.respond_to?(:resource_meta)
          ret = ret.merge(model.resource_meta)
        end
        if model.respond_to?(:resource_errors)
          errs = model.resource_errors
          ret[:errors] = errs if errs.present?
        end
        ret
      end

    end

    module ClassMethods

      def presets_to_serialize
        @presets_to_serialize ||= begin
          {
            basic: (attributes_to_serialize.try(:keys) || []),
            full: (attributes_to_serialize.try(:keys) || []) + (relationships_to_serialize.try(:keys) || [])
          }
        end
      end

      def default_fields(opts)
        preset(:default, opts)
      end

      def preset(name, opts)
        fields = opts
        if opts.is_a?(Hash)
          fields = []
          if opts[:with]
            opts[:with].each do |p|
              if p == :attributes
                fields = fields + attributes_to_serialize.keys
              else
                fields = fields + presets_to_serialize[p]
              end
            end
          end
          if opts[:fields]
            fields = fields + opts[:fields]
          end
          if opts[:exclude]
            fields = (attributes_to_serialize.try(:keys) || []) + (relationships_to_serialize.try(:keys) || []) if fields.empty?
            fields = fields - opts[:exclude]
          end
        end
        self.presets_to_serialize[name] = fields.map(&:to_sym).uniq
      end

      def default_fields_to_serialize
        if presets_to_serialize.nil? || presets_to_serialize[:default].nil?
          return nil
        else
          return presets_to_serialize[:default]
        end
      end

      def resolve_fieldset(fields)
        orig_fields = fields.dup
        # NOTE: This will directly modify fields array for speed
        if fields.nil?
          # handle default fields
          return default_fields_to_serialize
        end
        # resolve presets
        prefs = fields.select{|f| f.to_s.start_with?("...")}
        if prefs.length > 0
          #puts "Processing presets"
          fields.reject! {|f| f.start_with?("...")}
          prefs.each do |pref|
            pname = pref[3..-1]
            pname = "default" if pname == "" || pname == "defaults"
            pfs = presets_to_serialize[pname.to_sym]
            if pfs.nil?
              raise "Serializer preset #{pname} not found for #{record_type}."
            end
            fields.push(*pfs)
          end
        end
        #puts "Returning fields #{ret}"
        #binding.pry if fields && (fields.include?(:mins) || fields.include?('mins'))
        return fields
      end

      def record_hash(record, fieldset, includes_list, params={})
        # process fieldset
        fieldset = resolve_fieldset(fieldset)
        super(record, fieldset, includes_list, params)
      end

      def inherit_presets
        @presets_to_serialize = superclass.presets_to_serialize
      end

    end

  end

end
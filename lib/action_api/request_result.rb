module ActionAPI

  class RequestResult
    attr_accessor :data, :meta, :errors

    def initialize(data: nil, meta: nil, errors: [])
      self.data = data
      self.meta = meta
      self.errors = errors
    end

    def success?
      errors.blank?
    end
    alias_method :success, :success?

    def [](key)
      self.send(key)
    end

    def raise_if_error!
      if !success?
        raise errors.first
      end
    end

  end

end
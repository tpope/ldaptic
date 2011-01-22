module Ldapter
  class ErrorSet < Hash
    def initialize(base)
      @base = base
      super() { |h, k| h[k] = [] }
    end

    def add(attribute, message)
      self[attribute] << message
    end

    def each
      each_key do |attribute|
        self[attribute].each do |message|
          yield attribute, message
        end
      end
    end

    def full_messages
      map do |attribute, message|
        "#{@base.class.human_attribute_name(attribute)} #{message}"
      end
    end

    def to_a
      full_messages
    end

    def size
      full_messages.size
    end
  end
end

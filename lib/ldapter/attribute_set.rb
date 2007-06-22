module Ldapter
  class AttributeSet

    alias proxy_respond_to? respond_to?
    instance_methods.each { |m| undef_method m unless m =~ /(^__|^nil\?$|^send$|proxy_)/ }
    attr_reader :target

    def initialize(target, type, syntax, object)
      @target = target
      @type   = type
      @syntax = syntax
      @object = object
      if @type.nil?
        @object.logger.warn("ldapter") { "Unknown attribute type for #{key}" }
      elsif @syntax.nil?
        @object.logger.warn("ldapter") { "Unknown syntax #{type.syntax_oid} for attribute type #{Array(type.name).first}" }
      end
    end

    def method_missing(method,*args,&block)
      typecast(@target).send(method,*args,&block)
    end

    def ===(object)
      typecast(@target) === object
    end

    def respond_to?(method)
      proxy_respond_to?(method) || @target.respond_to?(method)
    end

    def add(*attributes)
      safe_array(attributes).each do |attribute|
        @target.push(attribute) unless self.include?(attribute)
      end
      self
    end

    alias <<     add
    alias concat add
    alias push   add

    def replace(*attributes)
      attributes = safe_array(attributes)
      if @type
        if @type.no_user_modification?
          raise Error, "read-only value", caller
        elsif @type.single_value? && attributes.size > 1
          raise TypeError, "multiple values for single-valued attribute", caller
        end
      end
      @target.replace(attributes)
      self
    end

    def clear
      @target.clear
      self
    end

    def delete(*attributes)
      safe_array(attributes).each do |attribute|
        @target.delete(attribute) do
          match = @target.detect {|x| x.downcase == attribute.downcase}
          @target.delete(match) if match
        end
      end
    end

    alias subtract delete

    def slice!(*args)
      value = args.pop
      typecast(
      if value.kind_of?(Array)
        @target.slice!(*(args+[safe_array(value)]))
      elsif value.nil?
        @target.delete_at(*args)
      else
        @target.slice!(*(args+safe_array(value)))
      end)
    end
    alias []= slice!

    def collect!
      @target.collect! do |value|
        format(yield(typecast(value)))
      end.compact!
      self
    end
    alias map! collect!

    def insert(index, *objects)
      @target.insert(index, *safe_array(objects))
      self
    end

    def unshift(*values)
      insert(0,*values)
    end

    def delete_if
      typecast(@target.delete_if { |value| yield(typecast(value)) })
    end

    def reject!
      typecast(@target.reject!   { |value| yield(typecast(value)) })
    end

    %w(at delete_at pop shift).each do |method|
      class_eval(<<-EOS,__FILE__,__LINE__)
        def #{method}(*args,&block)
         typecast(@target.__send__('#{method}',*args,&block))
        end
      EOS
    end

    %w(reverse! sort! uniq!).each do |method|
      class_eval(<<-EOS,__FILE__,__LINE__)
        def #{method}(*args)
          raise NotImplementedError
        end
      EOS
    end

    private

    def format(value)
      case value
      when Array then value.map {|x| format(x)}
      when nil   then nil
      else            @syntax ? @syntax.format(value) : value
      end
    end

    def safe_array(attributes)
      Array(attributes).flatten.map {|x| format(x)}
    end

    def typecast(value)
      case value
      when Array then value.map {|x| typecast(x)}
      when nil   then nil
      else            @syntax ? @syntax.parse(value) : value
      end
    end

  end
end

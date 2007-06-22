require 'ldap/escape'

module Ldapter
  class AttributeSet

    alias proxy_respond_to? respond_to?
    instance_methods.each { |m| undef_method m unless m =~ /(^__|^nil\?$|^proxy_)/ }
    attr_reader :target

    def initialize(object, key, target)
      @object = object
      @key    = LDAP.escape(key)
      @type   = @object.namespace.adapter.attribute_type(@key)
      @syntax = @type && @type.syntax
      @target = target
      if @type.nil?
        @object.logger.warn("ldapter") { "Unknown attribute type #{@key}" }
      elsif @syntax.nil?
        @object.logger.warn("ldapter") { "Unknown syntax #{@type.syntax_oid} for attribute type #{Array(@type.name).first}" }
      end
    end

    def method_missing(method,*args,&block)
      typecast(@target).__send__(method,*args,&block)
    end

    def ===(object)
      typecast(@target) === object
    end

    def respond_to?(method)
      proxy_respond_to?(method) || @target.respond_to?(method)
    end

    def add(*attributes)
      dest = @target.dup
      safe_array(attributes).each do |attribute|
        dest.push(attribute) unless self.include?(attribute)
      end
      replace(dest)
      self
    end

    alias <<     add
    alias concat add
    alias push   add

    def replace(*attributes)
      attributes = safe_array(attributes)
      if no_user_modification?
        raise TypeError, "read-only attribute #{@key}", caller
      elsif single_value? && attributes.size > 1
        raise TypeError, "multiple values for single-valued attribute #{@key}", caller
      elsif mandatory? && attributes.empty?
        raise TypeError, "value required for attribute #{@key}", caller
      end
      @target.replace(attributes)
      self
    end

    def clear
      replace([])
      self
    end

    def delete(*attributes,&block)
      dest = @target.dup
      ret = []
      safe_array(attributes).each do |attribute|
        ret << dest.delete(attribute) do
          match = dest.detect {|x| x.downcase == attribute.downcase}
          if match
            dest.delete(match)
          else
            yield(attribute)
          end
        end
      end
      replace(dest)
      if attributes.size == 1 && !attributes.first.kind_of?(Array)
        typecast ret.first
      else
        typecast ret
      end
    end

    alias subtract delete

    # TODO: refactor all mutating methods through replace
    def slice!(*args)
      value = args.pop
      typecast(
      if value.nil?
        @target.delete_at(*args)
      else
        @target.slice!(*(args+[format(value)]))
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

    def mandatory?
      @object.must.include?(@key)
    end

    def single_value?
      @type && @type.single_value?
    end

    def no_user_modification?
      @type && @type.no_user_modification?
    end

    # If the attribute is a SINGLE-VALUE, return it, otherwise, return self.
    def reduce
      if single_value?
        first
      else
        self
      end
    end

    private

    def syntax_object
      @syntax && @syntax.object.new(@object)
    end

    def format(value)
      case value
      when Array then value.map {|x| format(x)}
      when nil   then nil
      else
        value = @syntax ? syntax_object.format(value) : value
        if @type && @type.no_user_modification?
          value.dup.freeze if value.kind_of?(String)
        else
          value
        end
      end
    end

    def safe_array(attributes)
      Array(attributes).flatten.map {|x| format(x)}
    end

    def typecast(value)
      case value
      when Array then value.map {|x| typecast(x)}
      when nil   then nil
      else            @syntax ? syntax_object.parse(value) : value
      end
    end

  end
end

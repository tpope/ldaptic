require 'ldap/escape'

module Ldapter
  class AttributeSet

    alias proxy_respond_to? respond_to?
    instance_methods.each { |m| undef_method m unless m =~ /(^__|^nil\?$|^proxy_)/ }
    attr_reader :target

    def initialize(object, key, target)
      @object = object
      @key    = LDAP.escape(key)
      @type   = @object.namespace.attribute_type(@key)
      @syntax = @object.namespace.attribute_syntax(@key)
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

    # Add the desired attributes to the LDAP server immediately.
    def add!(*attributes)
      @object.add!(@key, safe_array(attributes))
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

    # Replace the entire attribute at the LDAP server immediately.
    def replace!(*attributes)
      @object.replace!(@key, safe_array(attributes))
      self
    end

    def clear
      replace([])
      self
    end

    def delete(*attributes,&block)
      return clear if attributes.flatten.empty?
      dest = @target.dup
      ret = []
      safe_array(attributes).each do |attribute|
        ret << dest.delete(attribute) do
          match = dest.detect {|x| x.downcase == attribute.downcase}
          if match
            dest.delete(match)
          else
            yield(attribute) if block_given?
          end
        end
      end
      replace(dest)
      if attributes.size == 1 && !attributes.first.kind_of?(Array)
        typecast ret.first
      else
        self
      end
    end
    alias subtract delete

    # Delete the desired values from the attribute at the LDAP server.
    # If no values are given, the entire attribute is removed.
    def delete!(*attributes)
      @object.delete!(@key, safe_array(attributes))
      self
    end

    def collect!(&block)
      replace(typecast(@target).collect(&block))
    end
    alias map! collect!

    def insert(index, *objects)
      replace(typecast(@target).insert(index, *objects.flatten))
    end

    def unshift(*values)
      insert(0,*values)
    end

    def reject!(&block)
      array = typecast(@target)
      replace(array) if array.reject!(&block)
    end

    def delete_if(&block)
      reject!(&block)
      self
    end

    %w(delete_at pop shift slice!).each do |method|
      class_eval(<<-EOS,__FILE__,__LINE__)
        def #{method}(*args,&block)
          array = typecast(@target)
          result = array.send('#{method}',*args,&block)
          replace(array)
          result
        end
      EOS
    end

    alias []= slice!

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

    attr_reader :type

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
      Array(attributes).flatten.compact.map {|x| format(x)}
    end

    def typecast(value)
      case value
      when Array then value.map {|x| typecast(x)}
      when nil   then nil
      else            @syntax ? syntax_object.parse(value) : value
      end
    end

    def clone_into_original_attributes
      originals = @object.instance_variable_get(:@original_attributes)
      originals[@key] = @target.map {|x| x.dup}
      self
    end

  end
end

require 'ldap/escape'

module Ldapter
  # AttributeSet, like the name suggests, represents a set of attributes.  Most
  # operations are delegated to an array, so the usual array methods should
  # work transparently.
  class AttributeSet

    alias proxy_respond_to? respond_to?
    instance_methods.each { |m| undef_method m unless m =~ /(^__|^send$|^funcall$|^equal\?$|^nil\?|^object_id$|^proxy_)/ }
    # attr_reader :target

    # The original attributes before type conversion.  Mutating the result
    # mutates the original attributes.
    def before_type_cast
      @target
    end

    def initialize(object, key, target) #:nodoc:
      @object = object
      @key    = LDAP.encode(key)
      @type   = @object.namespace.attribute_type(@key)
      @syntax = @object.namespace.attribute_syntax(@key)
      @target = target
      if @type.nil?
        @object.logger.warn("ldapter") { "Unknown attribute type #{@key}" }
      elsif @syntax.nil?
        @object.logger.warn("ldapter") { "Unknown syntax #{@type.syntax_oid} for attribute type #{Array(@type.name).first}" }
      end
    end

    # Delegates to an array.
    def method_missing(method,*args,&block)
      typecast(@target).send(method,*args,&block)
    end

    def ===(object) #:nodoc:
      typecast(@target) === object
    end

    def respond_to?(method) #:nodoc:
      proxy_respond_to?(method) || @target.respond_to?(method)
    end

    # Adds the given attributes, discarding duplicates.  Currently, a duplicate
    # is determined by == (case sensitive) rather than by the server (typically
    # case insensitive).  All arrays are flattened.
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

    # Does a complete replacement of the attributes.  Multiple attributes can
    # be given as either multiple arguments or as an array.
    def replace(*attributes)
      attributes = safe_array(attributes)
      if no_user_modification?
        Ldapter::Errors.raise(TypeError.new("read-only attribute #{@key}"))
      elsif single_value? && attributes.size > 1
        Ldapter::Errors.raise(TypeError.new("multiple values for single-valued attribute #{@key}"))
      elsif mandatory? && attributes.empty?
        Ldapter::Errors.raise(TypeError.new("value required for attribute #{@key}"))
      end
      @target.replace(attributes)
      self
    end

    # Replace the entire attribute at the LDAP server immediately.
    def replace!(*attributes)
      @object.replace!(@key, safe_array(attributes))
      self
    end

    def clear #:nodoc:
      replace([])
      self
    end

    # Remove the given attributes given, functioning more or less like
    # Array#delete, except accepting multiple arguments.
    #
    # Two passes are made to find each element, one case sensitive and one
    # ignoring case, before giving up.
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
        # typecast ret
        self
      end
    end

    # Delete the desired values from the attribute at the LDAP server.
    # If no values are given, the entire attribute is removed.
    def delete!(*attributes)
      @object.delete!(@key, safe_array(attributes))
      self
    end

    def collect!(&block) #:nodoc:
      replace(typecast(@target).collect(&block))
    end

    def insert(index, *objects) #:nodoc:
      replace(typecast(@target).insert(index, *objects.flatten))
    end

    def unshift(*values) #:nodoc:
      insert(0,*values)
    end

    def reject!(&block) #:nodoc:
      array = typecast(@target)
      replace(array) if array.reject!(&block)
    end

    def delete_if(&block) #:nodoc:
      reject!(&block)
      self
    end

    %w(delete_at pop shift slice!).each do |method|
      class_eval(<<-EOS,__FILE__,__LINE__)
        def #{method}(*args,&block)
          array = typecast(@target)
          result = array.#{method}(*args,&block)
          replace(array)
          result
        end
      EOS
    end

    %w(reverse! sort! uniq!).each do |method|
      class_eval(<<-EOS,__FILE__,__LINE__)
        def #{method}(*args)
          Ldapter::Errors.raise(NotImplementedError.new)
        end
      EOS
    end

    # Returns +true+ if the attribute is marked MUST in the object class.
    def mandatory?
      @object.must.include?(@key)
    end

    # Returns +true+ if the attribute may not be specified more than once.
    def single_value?
      @type && @type.single_value?
    end

    # Returns +true+ for read only attributes.
    def no_user_modification?
      @type && @type.no_user_modification?
    end

    # If the attribute is a single value, return it, otherwise, return self.
    def reduce
      if single_value?
        first
      else
        self
      end
    end

    attr_reader :type

    #:stopdoc:

    alias <<     add
    alias concat add
    alias push   add

    alias subtract delete

    alias map! collect!
    alias []= slice!

    #:startdoc:

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

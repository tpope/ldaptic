require 'ldapter/escape'

module Ldapter
  # AttributeSet, like the name suggests, represents a set of attributes.  Most
  # operations are delegated to an array, so the usual array methods should
  # work transparently.
  class AttributeSet

    attr_reader :entry, :name, :type, :syntax

    # The original attributes before type conversion.  Mutating the result
    # mutates the original attributes.
    def before_type_cast
      @target
    end

    def to_a
      typecast(@target)
    end
    alias to_ary to_a

    include Enumerable
    def each(&block)
      to_a.each(&block)
    end

    def initialize(entry, name, target)
      @entry  = entry
      @name   = Ldapter.encode(name)
      @type   = @entry.namespace.attribute_type(@name)
      @syntax = @entry.namespace.attribute_syntax(@name)
      @target = target
      if @type.nil?
        @entry.logger.warn("ldapter") { "Unknown attribute type #{@name}" }
      elsif @syntax.nil?
        @entry.logger.warn("ldapter") { "Unknown syntax #{@type.syntax_oid} for attribute type #{Array(@type.name).first}" }
      end
    end

    def errors
      errors = []
      if single_value? && @target.size > 1
        errors << "does not accept multiple values"
      elsif mandatory? && @target.empty?
        errors << "is mandatory"
      end
      if syntax_object
        errors += @target.map { |v| syntax_object.error(v) }.compact
      end
      errors
    end

    # Delegates to an array.
    def method_missing(method, *args, &block)
      to_a.send(method, *args, &block)
    end

    def ===(object)
      to_a === object
    end

    def eql?(object)
      to_a.eql?(object)
    end
    alias == eql?

    def respond_to?(method, *args) #:nodoc:
      super || @target.respond_to?(method, *args)
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
    alias <<     add
    alias concat add
    alias push   add

    # Add the desired attributes to the LDAP server immediately.
    def add!(*attributes)
      @entry.add!(@name, safe_array(attributes))
      self
    end

    # Does a complete replacement of the attributes.  Multiple attributes can
    # be given as either multiple arguments or as an array.
    def replace(*attributes)
      attributes = safe_array(attributes)
      if no_user_modification?
        Ldapter::Errors.raise(TypeError.new("read-only attribute #{@name}"))
      end
      @target.replace(attributes)
      self
    end

    # Replace the entire attribute at the LDAP server immediately.
    def replace!(*attributes)
      @entry.replace!(@name, safe_array(attributes))
      self
    end

    def clear
      replace([])
      self
    end

    # Remove the given attributes given, functioning more or less like
    # Array#delete, except accepting multiple arguments.
    #
    # Two passes are made to find each element, one case sensitive and one
    # ignoring case, before giving up.
    def delete(*attributes, &block)
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
      @entry.delete!(@name, safe_array(attributes))
      self
    end

    def collect!(&block)
      replace(to_a.collect(&block))
    end
    alias map! collect!

    def insert(index, *objects)
      replace(to_a.insert(index, *objects.flatten))
    end

    def unshift(*values)
      insert(0, *values)
    end

    def reject!(&block)
      array = to_a
      replace(array) if array.reject!(&block)
    end

    def delete_if(&block)
      reject!(&block)
      self
    end

    %w(delete_at pop shift slice!).each do |method|
      class_eval(<<-EOS, __FILE__, __LINE__.succ)
        def #{method}(*args, &block)
          array = to_a
          result = array.#{method}(*args, &block)
          replace(array)
          result
        end
      EOS
    end
    alias []= slice!

    %w(reverse! sort! uniq!).each do |method|
      class_eval(<<-EOS, __FILE__, __LINE__.succ)
        def #{method}(*args)
          Ldapter::Errors.raise(NotImplementedError.new)
        end
      EOS
    end

    # Returns +true+ if the attribute is marked MUST in the object class.
    def mandatory?
      @entry.must.include?(@name)
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

    def to_s
      @target.join("\n")
    end

    def inspect
      "<#{to_a.inspect}>"
    end

    def as_json(*args) #:nodoc:
      to_a.as_json(*args)
    end

    def syntax_object
      @syntax && @syntax.object.new(@entry)
    end

    private

    def format(value)
      value = @syntax ? syntax_object.format(value) : value
      if no_user_modification? && value.kind_of?(String)
        value.dup.freeze
      else
        value
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

  end
end

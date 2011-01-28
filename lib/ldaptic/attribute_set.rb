require 'ldaptic/escape'

module Ldaptic
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
      @name   = Ldaptic.encode(name)
      @type   = @entry.namespace.attribute_type(@name)
      @syntax = @entry.namespace.attribute_syntax(@name)
      @target = target
      if @type.nil?
        @entry.logger "Unknown type for attribute #@name"
      elsif @syntax.nil?
        @entry.logger "Unknown syntax #{@type.syntax_oid} for attribute #{@name}"
      end
    end

    def errors
      return ['is forbidden'] if forbidden? && !empty?
      errors = []
      if single_value? && size > 1
        errors << "does not accept multiple values"
      elsif mandatory? && empty?
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

    def size
      @target.size
    end

    def empty?
      @target.empty?
    end

    def index(*args, &block)
      if block_given? || args.size != 1
        return to_a.index(*args, &block)
      else
        target = matchable(args.first)
        @target.each_with_index do |candidate, index|
          return index if matchable(candidate) == target
        end
      end
      nil
    end
    alias find_index index
    alias rindex index

    def include?(target)
      !!index(target)
    end

    def exclude?(target)
      !index(target)
    end

    # Adds the given attributes, discarding duplicates.  Currently, a duplicate
    # is determined by == (case sensitive) rather than by the server (typically
    # case insensitive).  All arrays are flattened.
    def add(*attributes)
      dest = @target.dup
      safe_array(attributes).each do |attribute|
        dest.push(attribute) unless include?(attribute)
      end
      replace(dest)
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
      user_modification_guard
      seen = {}
      filtered = []
      attributes.each do |value|
        matchable = matchable(value)
        unless seen[matchable]
          filtered << value
          seen[matchable] = true
        end
      end
      @target.replace(filtered)
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
      replace(@target.dup.insert(index, *safe_array(objects)))
      self
    end

    def unshift(*values)
      insert(0, *values)
    end

    def reject!(&block)
      user_modification_guard
      @target.reject! do |value|
        yield(typecast(value))
      end
    end

    def delete_if(&block)
      reject!(&block)
      self
    end

    %w(delete_at pop shift slice!).each do |method|
      class_eval(<<-EOS, __FILE__, __LINE__.succ)
        def #{method}(*args, &block)
          user_modification_guard
          typecast(@target.#{method}(*args, &block))
        end
      EOS
    end
    alias []= slice!

    %w(reverse! shuffle! sort! uniq!).each do |method|
      class_eval(<<-EOS, __FILE__, __LINE__.succ)
        def #{method}(*args)
          Ldaptic::Errors.raise(NotImplementedError.new)
        end
      EOS
    end

    # Returns +true+ if the attribute is marked neither MUST nor MAY in the
    # object class.
    def forbidden?
      !(@entry.must + @entry.may).include?(@name)
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
    def one
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

    # Invokes +human_attribute_name+ on the attribute's name.
    def human_name
      @entry.class.human_attribute_name(@name)
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

    def matchable(value)
      format(value)
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

    def user_modification_guard
      if no_user_modification?
        Ldaptic::Errors.raise(TypeError.new("read-only attribute #{@name}"))
      end
    end

  end
end

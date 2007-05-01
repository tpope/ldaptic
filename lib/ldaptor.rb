#!/usr/bin/ruby
# $Id$
# -*- ruby -*- vim:set ft=ruby et sw=2 sts=2:

require 'ldap'
require 'ldaptor/schema'
require 'ldap/filter'

module Ldaptor

  # RFC 2252.  Second column is "Human Readable"
  SYNTAX_STRING = <<-EOF unless defined? SYNTAX_STRING
ACI Item                        N  1.3.6.1.4.1.1466.115.121.1.1
Access Point                    Y  1.3.6.1.4.1.1466.115.121.1.2
Attribute Type Description      Y  1.3.6.1.4.1.1466.115.121.1.3
Audio                           N  1.3.6.1.4.1.1466.115.121.1.4
Binary                          N  1.3.6.1.4.1.1466.115.121.1.5
Bit String                      Y  1.3.6.1.4.1.1466.115.121.1.6
Boolean                         Y  1.3.6.1.4.1.1466.115.121.1.7
Certificate                     N  1.3.6.1.4.1.1466.115.121.1.8
Certificate List                N  1.3.6.1.4.1.1466.115.121.1.9
Certificate Pair                N  1.3.6.1.4.1.1466.115.121.1.10
Country String                  Y  1.3.6.1.4.1.1466.115.121.1.11
DN                              Y  1.3.6.1.4.1.1466.115.121.1.12
Data Quality Syntax             Y  1.3.6.1.4.1.1466.115.121.1.13
Delivery Method                 Y  1.3.6.1.4.1.1466.115.121.1.14
Directory String                Y  1.3.6.1.4.1.1466.115.121.1.15
DIT Content Rule Description    Y  1.3.6.1.4.1.1466.115.121.1.16
DIT Structure Rule Description  Y  1.3.6.1.4.1.1466.115.121.1.17
DL Submit Permission            Y  1.3.6.1.4.1.1466.115.121.1.18
DSA Quality Syntax              Y  1.3.6.1.4.1.1466.115.121.1.19
DSE Type                        Y  1.3.6.1.4.1.1466.115.121.1.20
Enhanced Guide                  Y  1.3.6.1.4.1.1466.115.121.1.21
Facsimile Telephone Number      Y  1.3.6.1.4.1.1466.115.121.1.22
Fax                             N  1.3.6.1.4.1.1466.115.121.1.23
Generalized Time                Y  1.3.6.1.4.1.1466.115.121.1.24
Guide                           Y  1.3.6.1.4.1.1466.115.121.1.25
IA5 String                      Y  1.3.6.1.4.1.1466.115.121.1.26
INTEGER                         Y  1.3.6.1.4.1.1466.115.121.1.27
JPEG                            N  1.3.6.1.4.1.1466.115.121.1.28
LDAP Syntax Description         Y  1.3.6.1.4.1.1466.115.121.1.54
LDAP Schema Definition          Y  1.3.6.1.4.1.1466.115.121.1.56
LDAP Schema Description         Y  1.3.6.1.4.1.1466.115.121.1.57
Master And Shadow Access Points Y  1.3.6.1.4.1.1466.115.121.1.29
Matching Rule Description       Y  1.3.6.1.4.1.1466.115.121.1.30
Matching Rule Use Description   Y  1.3.6.1.4.1.1466.115.121.1.31
Mail Preference                 Y  1.3.6.1.4.1.1466.115.121.1.32
MHS OR Address                  Y  1.3.6.1.4.1.1466.115.121.1.33
Modify Rights                   Y  1.3.6.1.4.1.1466.115.121.1.55
Name And Optional UID           Y  1.3.6.1.4.1.1466.115.121.1.34
Name Form Description           Y  1.3.6.1.4.1.1466.115.121.1.35
Numeric String                  Y  1.3.6.1.4.1.1466.115.121.1.36
Object Class Description        Y  1.3.6.1.4.1.1466.115.121.1.37
Octet String                    Y  1.3.6.1.4.1.1466.115.121.1.40
OID                             Y  1.3.6.1.4.1.1466.115.121.1.38
Other Mailbox                   Y  1.3.6.1.4.1.1466.115.121.1.39
Postal Address                  Y  1.3.6.1.4.1.1466.115.121.1.41
Protocol Information            Y  1.3.6.1.4.1.1466.115.121.1.42
Presentation Address            Y  1.3.6.1.4.1.1466.115.121.1.43
Printable String                Y  1.3.6.1.4.1.1466.115.121.1.44
Substring Assertion             Y  1.3.6.1.4.1.1466.115.121.1.58
Subtree Specification           Y  1.3.6.1.4.1.1466.115.121.1.45
Supplier Information            Y  1.3.6.1.4.1.1466.115.121.1.46
Supplier Or Consumer            Y  1.3.6.1.4.1.1466.115.121.1.47
Supplier And Consumer           Y  1.3.6.1.4.1.1466.115.121.1.48
Supported Algorithm             N  1.3.6.1.4.1.1466.115.121.1.49
Telephone Number                Y  1.3.6.1.4.1.1466.115.121.1.50
Teletex Terminal Identifier     Y  1.3.6.1.4.1.1466.115.121.1.51
Telex Number                    Y  1.3.6.1.4.1.1466.115.121.1.52
UTC Time                        Y  1.3.6.1.4.1.1466.115.121.1.53
EOF

  SYNTAXES = {} unless defined? SYNTAXES
  SYNTAX_STRING.each_line do |line|
    a, b = line.chomp.split(/ [YN]  /)
    a.rstrip!
    SYNTAXES[b] = a
  end

  module Syntaxes

    module DirectoryString
      def self.parse(string)
        string
      end
      def self.format(string)
        string.to_str
      end
    end

    module Boolean
      def self.parse(string)
        return string == "TRUE"
      end
      def self.format(boolean)
        case boolean
        when "TRUE",  true  then "TRUE"
        when "FALSE", false then "FALSE"
        else raise TypeError, "boolean expected", caller
        end
      end
    end

    module INTEGER
      def self.parse(string)
        return string.to_i
      end
      def self.format(integer)
        Integer(integer).to_s
      end
    end

    module GeneralizedTime
      def self.parse(string)
        require 'time'
        Time.parse(string)
      end
      def self.format(time)
        time.utc.strftime("%Y%m%d%H%M%S")+".%06dZ" % (time.usec/100_000)
      end
    end

  end

  class SchemaLine

    def self.attr_boolean_schema(*attrs)
      attr_ldap_reader(*attrs)
      @hash ||= {}
      attrs.each do |attr|
        @hash[attr.to_s.upcase.to_s.gsub('_','-')] = :boolean
      end
    end

    def self.attr_string_schema(*attrs)
      attr_ldap_reader(*attrs)
      @hash ||= {}
      attrs.each do |attr|
        @hash[attr.to_s.upcase.to_s.gsub('_','-')] = :string
      end
    end

    def self.attr_array_schema(*attrs)
      attr_ldap_reader(*attrs)
      @hash ||= {}
      attrs.each do |attr|
        @hash[attr.to_s.upcase.to_s.gsub('_','-')] = :array
      end
    end

    def self.attr_ldap_reader(*attrs)
      attrs.each do |attr|
        class_eval(<<-EOS)
          def #{attr.to_s.downcase.gsub('-','_')}
            @hash[#{attr.to_s.upcase.gsub('_','-').inspect}]
          end
        EOS
      end
    end

    attr_accessor :oid
    def self.attributes
      @hash ||= {}
    end

    def initialize(string)
      @string = string.dup
      string = @string.dup
      # raise string unless string =~ /^\(\s*(\d[.\d]*\d) (.*?)\s*\)\s*$/
      string.gsub!(/^\s*\(\s*(\d[\d.]*\d)\s*(.*?)\s*\)\s*$/,'\\2')
      @oid = $1
      @hash = {}
      while value = eat(string,/^\s*([A-Z-]+)\s*/)
        if self.class.attributes[value] == :string
          @hash[value] = eatstr(string)
        elsif self.class.attributes[value] == :array
          @hash[value] = eatary(string)
        elsif self.class.attributes[value] == :boolean
          @hash[value] = true
        elsif value =~ /^X-/
          eatstr(string)
        end
      end
    end

    def to_s
      name
    end

    def eat(string,regex)
      string.gsub!(regex,'')
      $1 || $&
    end
    def eatstr(string)
      if eaten = eat(string, /^\(\s*'([^)]+)'\s*\)/i)
        eaten.split("' '").collect{|attr| attr.strip }
      else
        eat(string,/^'([^']*)'\s*/)
      end
    end

    def eatary(string)
      if eaten = eat(string, /^\(([\w\d_\s\$-]+)\)/i)
        eaten.split("$").collect{|attr| attr.strip}
      else
        eat(string,/^([\w\d_-]+)/i)
      end
    end

  end

  class AttributeType < SchemaLine
    attr_boolean_schema :obsolete, :single_value, :collective, :no_user_modification
    attr_string_schema  :name, :desc, :sup, :equality, :ordering, :substr, :syntax, :usage
  end

  class ObjectClass < SchemaLine
    attr_boolean_schema :structural, :auxiliary, :abstract, :obsolete
    attr_string_schema  :name, :desc
    attr_array_schema   :sup, :may, :must
  end

  class Error < ::RuntimeError #:nodoc:
  end

  class RecordNotFound < Error
  end

  def self.build_hierarchy(connection,base_dn = nil,&block)
    klass = Class.new(Base)
    klass.connection = connection
    klass.base_dn = base_dn
    klass.send(:build_hierarchy)
    klass.instance_eval(&block) if block_given?
    klass
  end

  def self.Namespace(connection, base_dn = nil)
    klass = Class.new(Base)
    klass.connection = connection
    klass.base_dn = base_dn
    klass.instance_variable_set(:@name, false)
    klass
  end

  class Base

    def initialize(data = {})
      raise TypeError, "abstract class initialized", caller if self.class.name.nil? || self.class.abstract?
      @data = data
    end

    def dn
      @data["dn"].first
    end

    def connection
      self.class.connection
    end

    def read_attribute(key)
      key = keyify(key)
      values = @data[key]
      return nil if values.nil?
      at = self.class.attribute_types[key]
      return values unless at
      if syn = SYNTAXES[at.syntax]
        if syn == 'DN'
          values = values.map do |value|
            ldaptor = self.class
            while ldaptor.superclass.respond_to?(:connection) && ldaptor.superclass.connection == self.connection
              ldaptor = ldaptor.superclass
            end
            value.instance_variable_set(:@ldaptor,ldaptor)
            def value.find
              @ldaptor.find(self)
            end
            value
          end
        else
          parser = Ldaptor::Syntaxes.const_get(syn.gsub(' ','')) rescue Ldaptor::Syntaxes::DirectoryString
          values = values.map do |value|
            parser.parse(value)
          end
        end
      end
      if at && at.single_value
        values.first
      else
        values
      end
    end

    def write_attribute(key,values)
      key = keyify(key)
      at = self.class.attribute_types[key]
      unless at
        warn "Unknown attribute type #{key}"
        @data[key] = Array(values)
        return values
      end
      if at.no_user_modification
        raise Error, "read-only value", caller
      end
      if at.single_value
        values = [values].flatten.compact
      end
      raise TypeError, "array expected", caller unless values.kind_of?(Array)
      if must.include?(key) && values.empty?
        raise TypeError, "value required", caller
      end
      if syn = SYNTAXES[at.syntax]
        if syn == 'DN'
          values = values.map do |value|
            value.respond_to?(:dn) ? value.dn : value
          end
        else
          parser = Ldaptor::Syntaxes.const_get(syn.gsub(' ','')) rescue Ldaptor::Syntaxes::DirectoryString
          values = values.map do |value|
            parser.format(value)
          end
        end
      end
      @data[key] = values
    end

    def must
      return self.class.must
    end

    def may
      # TODO: account for AUX
      return self.class.may

      may = []
      @data["objectClass"].reverse.each do |oc|
        may += self.class.schema.may(oc).to_a
        aux = self.class.schema.aux(oc).to_a
        aux.each do |oc2|
          may += self.class.schema.may(oc2).to_a
        end
      end
      may.uniq!
      may + must
    end

    def may_must(attribute)
      attribute = attribute.to_s
      if may.include?(attribute)
        :may
      elsif must.include?(attribute)
        :must
      end
    end

    def method_missing(method,*args,&block)
      method = method.to_s
      attribute = method.gsub('_','-')
      if attribute[-1] == ?= && @data.has_key?(attribute[0..-2])
        attribute.chop!
        write_attribute(attribute,*args,&block)
      elsif @data.has_key?(attribute)
        read_attribute(attribute,*args,&block)
      elsif @data.respond_to?(method)
        @data.send(method,*args,&block)
      else
        # Does not work
        extensions = self.class.const_get("Extensions") rescue nil
        if extensions
          @data["objectClass"].reverse.each do |oc|
            oc[0..0] = oc[0..0].upcase
            if extensions.constants.include?(oc)
              p oc
              extension = extensions.const_get(oc)
              if extension.instance_methods.include?(method)
                p method
                im = extension.instance_method(method).bind(self)
                im.call(*args)
              end
            end
          end
        end
        super
      end
    end

    private
    def keyify(key)
      key.kind_of?(Symbol) ? key.to_s.gsub('_','-') : key.dup
    end

    class << self

      def self.inheritable_accessor(*names)
        names.each do |name|
          define_method name do
            val = instance_variable_get("@#{name}")
            return val unless val.nil?
            return superclass.send(name) if superclass.respond_to?(name)
          end
          define_method "#{name}=" do |value|
            instance_variable_set("@#{name}",value)
          end
        end
      end

      inheritable_accessor :connection, :base_dn

      attr_reader :oid, :name, :desc, :obsolete, :sup, :abstract, :structural, :auxiliary, :must, :may
      %w(obsolete abstract structural auxiliary).each do |attr|
        class_eval("def #{attr}?; !! @#{attr}; end")
      end

      def ldap_ancestors
        ancestors.select {|o| o.ancestors.include?(Base) && o != Base && o.name != false}
      end

      def root
        ldap_ancestors.last
      end

      def may(all = true)
        if all
          ldap_ancestors.collect do |klass|
            Array(klass.may(false))
          end.flatten
        else
          @may
        end
      end

      def must(all = true)
        if all
          ldap_ancestors.collect do |klass|
            Array(klass.must(false))
          end.flatten
        else
          @must
        end
      end

      def schema
        @schema ||= connection.schema
      end

      def attributes(all = true)
        may(all) + must(all)
      end

      def attribute_types
        @attrs ||= schema["attributeTypes"].inject({}) do |hash,val|
          at = Ldaptor::AttributeType.new(val)
          hash[at.oid] = at
          hash[at.name] = at
          hash
        end
        @attrs
      end

      def object_class
        @object_class || Array(@name).first
      end

      def object_classes
        ldap_ancestors.map {|a| a.object_class}.compact.reverse.uniq
      end

      def inherited(subclass)
        @subclasses ||= []
        @subclasses << subclass
        if name == false
          subclass.send(:build_hierarchy)
        end
        super
      end

      def build_hierarchy
        raise TypeError, "cannot build hierarchy for a named class", caller if name
        klasses = connection.schema["objectClasses"].map do |k|
          Ldaptor::ObjectClass.new(k)
        end.compact
        add_constants(self,klasses,self)
      end

      def add_constants(mod,klasses,superclass)
        klasses.each do |sub|
          if Array(superclass.name).include?(sub.sup) || superclass.name == nil && sub.sup == nil
            klass = Class.new(superclass)
            %w(oid name desc obsolete sup abstract structural auxiliary must may).each do |prop|
              klass.instance_variable_set("@#{prop}", sub.send(prop))
            end
            klass.instance_variable_set(:@module, mod)
            Array(sub.name).each do |name|
              mod.const_set(name.ldapitalize(true), klass)
            end
            add_constants(mod, klasses, klass)
          end
        end
      end
      private :add_constants

      def wrap_object(r)
        subclasses = @subclasses || []
        if klass = subclasses.find {|c| r["objectClass"].to_a.include?(c.object_class)}
          klass.send(:wrap_object,r)
        else
          obj = allocate
          obj.instance_variable_set(:@data,r)
          obj
        end
      end
      private :wrap_object

      def search_raw(query_or_options, options = {})
        if query_or_options.kind_of?(Hash)
          raise unless options == {}
          options = query_or_options
          query_or_options = nil
        end
        query = query_or_options || options[:filter]
        scope = options[:scope] || LDAP::LDAP_SCOPE_SUBTREE
        case options[:sort]
        when Proc, Method then s_attr, s_proc = nil, options[:sort]
        else s_attr, s_proc = options[:sort], nil
        end
        query = {:objectClass => true} if query.nil?
        query = LDAP::Filter(query)
        query &= {:objectClass => object_class} if object_class
        connection.search2(
          options[:base_dn] || self.base_dn.to_s,
          scope,
          query.to_s,
          options[:attributes],
          false,
          options[:timeout].to_i,
          ((options[:timeout].to_f % 1) * 1e6).round,
          s_attr.to_s, s_proc
        )
      end
      private :search_raw

      def search(*args)
        search_raw(*args).map {|r| wrap_object(r)}
      end

      def find(dn,options = {})
        case dn
        when :all   then search(options)
        when :first then search_raw(options).first(1).map {|r| wrap_object(r)}.first
        when Array  then dn.map {|d| find_one(d,options)}
        else             find_one(dn,options)
        end
      end

      def find_one(dn,options)
        objects = search(options.merge(:base_dn => dn, :scope => LDAP::LDAP_SCOPE_BASE))
        unless objects.size == 1
          raise RecordNotFound, "record not found for #{dn}", caller
        end
        objects.first
      end
      private :find_one

    end

  end

end

class String
  def ldapitalize!(upper = false)
    self[0,1] = self[0,1].send(upper ? :upcase : :downcase)
    self.gsub!('-','_')
    self
  end

  def ldapitalize(upper = false)
    dup.ldapitalize!(upper)
  end
end

if __FILE__ == $0
  # class LocalLdaptor < Ldaptor::Base
    # self.connection = LDAP::Conn.new(`hostname -f`.chomp)
    # connection.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3)
    # self.base_dn = `hostname -f`.chomp.split(".").map {|x|"dc=#{x}"}[1..-1] * ","
    # connection.bind("cn=admin,#{base_dn}","ldaptor")
  # end
  require 'irb'
  IRB.start($0)
end


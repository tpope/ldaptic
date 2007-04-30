#!/usr/bin/ruby
# $Id$
# -*- ruby -*- vim:set ft=ruby et sw=2 sts=2:

require 'ldap'
require 'ldap/schema'
require 'ldap/filter'
# SYNTAXES = {
  # "1.3.6.1.4.1.1466.115.121.1.44" => String,
  # "1.3.6.1.4.1.1466.115.121.1.15" => "DirectoryString"
# }

module LDAP

  class Schema
    def aux(oc)
      self["dITContentRules"].to_a.each do |s|
        if s =~ /NAME\s+'#{oc}'/
          case s
          when /AUX\s+\(([\w\d_\s\$-]+)\)/i
            return $1.split("$").collect{|attr| attr.strip}
          when /AUX\s+([\w\d_-]+)/i
            return $1.split("$").collect{|attr| attr.strip}
          end
        end
      end
      return nil
    end
  end
end

module Ldaptor

  # RFC 2252.  Second column is "Human Readable"
SYNTAX_STRING = <<EOF unless defined? SYNTAX_STRING
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
    line.chomp!
    a, b = line.split(/ [YN]  /)
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
        time.utc.strftime("%Y%m%d%H%M%S")+".#{time.usec/100_000}Z"
      end
    end

  end

  class AttributeType
    def initialize(string)
      @string = string.dup
      string = @string.dup
      # raise string unless string =~ /^\(\s*(\d[.\d]*\d) (.*?)\s*\)\s*$/
      string.gsub!(/^\s*\(\s*(\d[\d.]*\d)\s*(.*?)\s*\)\s*$/,'\\2')
      @oid = $1
      while value = eat(string,/^\s*([A-Z-]+)\s*/)
        case value
        when "NAME"         then @name     = eatstr(string)
        when "DESC"         then @desc     = eatstr(string)
        when "OBSOLETE"     then @obsolete = true
        when "SUP"          then @sup      = eatstr(string)
        when "EQUALITY"     then @equality = eatstr(string)
        when "ORDERING"     then @ordering = eatstr(string)
        when "SUBSTR"       then @substr   = eatstr(string)
        when "SYNTAX"       then @syntax   = eatstr(string)
        when "SINGLE-VALUE" then @single_value = true
        when "COLLECTIVE"   then @collective = true
        when "NO-USER-MODIFICATION" then @no_user_modification = true
        when "USAGE"        then @usage = eatstr(string)
        when /^X-/          then eatstr(string)
        end
      end
    end
    attr_accessor :oid, :syntax, :name, :single_value, :no_user_modification, :string
    def to_s
      name
    end

    def eat(string,regex)
      string.gsub!(regex,'')
      $1 || $&
    end
    def eatstr(string)
      x = eat(string,/^'([^']*)'\s*/)
      # p x
      x
    end
  end

  class Error < ::RuntimeError #:nodoc:
  end

  class RecordNotFound < Error
  end

  class Base

    def initialize(data)
      # @host, @port = host, port
      # @base_dn = dn
      # @login, @password = login, password
      # @connection = LDAP::Conn.new(@host, @port)
      # @connection.bind(@login,@password)
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
            value.instance_variable_set(:@ldaptor,self.class)
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
        if values.nil?
          @data[key] = []
        elsif values.respond_to?(:to_ary)
          @data[key] = values
        else
          @data[key] = [values]
        end
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
      must = []
      @data["objectClass"].reverse.each do |oc|
        must += self.class.schema.must(oc).to_a
        aux = self.class.schema.aux(oc).to_a
        aux.each do |oc2|
          must += self.class.schema.must(oc2).to_a
        end
      end
      must.uniq!
      must
    end

    def may
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
      @data["objectClass"].reverse.each do |oc|
        if self.class.schema.may(oc).to_a.include?(attribute)
          return :may
        elsif self.class.schema.must(oc).to_a.include?(attribute)
          return :must
        end
      end
      nil
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

      def schema
        @schema ||= connection.schema
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

      def wrap_object(r)
        r.instance_variable_set(:@connection,self)
        def r.read_attribute(key)
          values = self[key] || []
          at = @connection.attribute_types[key]
          return values unless at
          if syn = SYNTAXES[at.syntax]
            if syn == 'DN'
              values.map! do |value|
              value.instance_variable_set(:@connection,@connection)
              def value.find
                @connection.find(self)
              end
              value
              end
            else
              parser = Ldaptor::Syntaxes.const_get(syn.gsub(' ','')) rescue Ldaptor::Syntaxes::DirectoryString
              values.map! do |value|
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
        r["objectClass"].each do |oc|
          # schema = @connection.schema
          (schema.may(oc).to_a + schema.must(oc).to_a).each do |attr|
            at = attribute_types[attr]
            r.instance_eval(<<-EOS)
              def #{attr.gsub('-','_')}
                read_attribute(#{attr.inspect})
              end
              def #{attr.gsub('-','_')}=(value)
                write_attribute(#{attr.inspect},value)
              end
            EOS
          end
        end
        obj = allocate
        obj.instance_variable_set(:@data,r)
        obj
      end
      private :wrap_object

      def search(query, scope = LDAP::LDAP_SCOPE_SUBTREE)
        @connection.search2("#{@base_dn}",scope,LDAP::Filter.new(query).to_s).map do |r|
          wrap_object(r)
        end
      end

      def find(dn)
        objects = @connection.search2(dn,LDAP::LDAP_SCOPE_BASE,"(objectclass=*)")
        unless objects.size == 1
          raise RecordNotFound, "record not found for #{dn}", caller
        end
        wrap_object(objects.first)
      end
    end

  end

end

if __FILE__ == $0
  # class LocalLdaptor < Ldaptor::Base
    # self.connection = LDAP::Conn.new("localhost")
    # connection.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3)
    # self.base_dn = `hostname -f`.chomp.split(".").map {|x|"dc=#{x}"} * ","
    # connection.bind("cn=admin,#{base_dn}","ldaptor")
  # end
  require 'irb'
  IRB.start($0)
end


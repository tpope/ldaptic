#!/usr/bin/ruby
# $Id$
# -*- ruby -*- vim:set ft=ruby et sw=2 sts=2:

require 'ldaptor/core_ext'
require 'ldap/filter'
require 'ldap/dn'
require 'ldap'
require 'ldaptor/schema'
require 'ldaptor/syntaxes'

module Ldaptor

  SCOPES = {
    :base     => ::LDAP::LDAP_SCOPE_BASE,
    :onelevel => ::LDAP::LDAP_SCOPE_ONELEVEL,
    :subtree  => ::LDAP::LDAP_SCOPE_SUBTREE
  }

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
      @data = data.dup
      @dn = @data.delete('dn')
    end

    def dn
      LDAP::DN(@dn || @data['dn'].first)
    end

    def parent
      ary = self.dn.split('=')
      dn = ary[1][/,([^,=]*)$/,1] + '=' + ary[2..-1].join('=')
      self.class.root.find(dn)
    end

    def children(type = nil, name = nil)
      if name && name != true
        search(:base_dn => "#{type}=#{LDAP.escape(name)},#{dn}", :scope => LDAP::LDAP_SCOPE_BASE).first
      elsif type
        search(:filter => {type => true}, :scope => LDAP::LDAP_SCOPE_ONELEVEL)
      else
        search(:scope => LDAP::LDAP_SCOPE_ONELEVEL)
      end
    end

    def connection
      self.class.connection
    end

    def read_attribute(key)
      key = attributify(key)
      values = @data[key]
      return nil if values.nil?
      at = self.class.attribute_types[key]
      return values unless at
      if syn = SYNTAXES[at.syntax]
        if syn == 'DN'
          values = values.map do |value|
            # ldaptor = self.class
            # while ldaptor.superclass.respond_to?(:connection) && ldaptor.superclass.connection == self.connection
              # ldaptor = ldaptor.superclass
            # end
            # value.instance_variable_set(:@ldaptor,ldaptor)
            # def value.find
              # @ldaptor.find(self)
            # end
            # value
            ::LDAP::DN(value,self)
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
      key = attributify(key)
      at = self.class.attribute_types[key]
      unless at
        warn "Warning: unknown attribute type for #{key}"
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

    def attributes
      @data
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
      attribute = attributify(method)
      if attribute[-1] == ?= && self.class.has_attribute?(attribute[0..-2])
        attribute.chop!
        write_attribute(attribute,*args,&block)
      elsif args.size == 1
        children(method,*args)
      elsif self.class.has_attribute?(attribute)
        read_attribute(attribute,*args,&block)
      elsif @data.respond_to?(method)
        @data.send(method,*args,&block)
      else
        super(method.to_sym,*args,&block)
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
      end
    end

    def search(options)
      self.class.root.search({:base_dn => self.dn}.merge(options))
    end

    def [](value)
      case value
      when /\(.*=/, Hash, LDAP::Filter
        search(:filter => value, :scope => LDAP::LDAP_SCOPE_ONELEVEL)
      when /=/, Array
        base_dn = [LDAP::DN(value),dn].join(",")
        search(
          :base_dn => base_dn,
          :scope => LDAP::LDAP_SCOPE_BASE
        ).first
      else read_attribute(value)
      end
    end

    def save
      if @new_record
        connection.add(dn, @data.reject {|k,v| k == "dn"})
        @new_record = false
      else
        connection.modify(dn, @data.reject {|k,v| k == "dn"})
      end
    end

    private
    def attributify(key)
      key.kind_of?(Symbol) ? key.to_s.gsub('_','-') : key.dup
    end

    class << self

      def has_attribute?(attribute)
        attribute = attribute.to_s.gsub('_','-')
        may.include?(attribute) || must.include?(attribute)
      end

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

      attr_reader :oid, :name, :desc, :sup
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
          end.flatten.uniq
        else
          @may
        end
      end

      def must(all = true)
        if all
          ldap_ancestors.collect do |klass|
            Array(klass.must(false))
          end.flatten.uniq
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
          Array(at.name).each do |name|
            hash[name] = at
          end
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

      def instantiate(attributes)
        subclasses = @subclasses || []
        if klass = subclasses.find {|c| attributes["objectClass"].to_a.include?(c.object_class)}
          return klass.send(:instantiate,attributes)
        elsif klass = root.const_get(attributes["objectClass"].last.to_s.ldapitalize(true)) rescue nil
          if klass != self
            return klass.send(:instantiate,attributes)
          end
        end
        obj = allocate
        obj.instance_variable_set(:@dn,attributes.delete('dn'))
        obj.instance_variable_set(:@data,attributes)
        obj
      end
      protected :instantiate

      def children(type = nil, name = nil)
        if name
          find("#{type}=#{LDAP.escape(name)},#{base_dn}")
        elsif type
          search(:filter => {type => true}, :scope => LDAP::LDAP_SCOPE_ONELEVEL)
        else
          search(:scope => LDAP::LDAP_SCOPE_ONELEVEL)
        end
      end

      def method_missing(method,*args,&block)
        if args.size == 1
          children(method.to_s.ldapitalize,*args)
        else
          super
        end
      end

      def search_raw(query_or_options, options = {})
        if query_or_options.kind_of?(Hash)
          raise unless options == {}
          options = query_or_options
          query_or_options = nil
        end
        query = query_or_options || options[:filter]
        scope = ::Ldaptor::SCOPES[options[:scope]] || options[:scope] || ::LDAP::LDAP_SCOPE_SUBTREE
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
        search_raw(*args).map {|r| instantiate(r)}
      end

      def find(dn,options = {})
        case dn
        when :all   then search(options)
        when :first then search_raw(options).first(1).map {|r| instantiate(r)}.first
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


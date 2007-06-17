#!/usr/bin/ruby
# $Id$
# -*- ruby -*- vim:set ft=ruby et sw=2 sts=2:

require 'ldaptor/core_ext'
require 'ldap/dn'
require 'ldap/filter'
# require 'ldap'
require 'ldaptor/schema'
require 'ldaptor/syntaxes'
require 'ldaptor/adapters'

module Ldaptor

  SCOPES = {
    :base     => 0, # ::LDAP::LDAP_SCOPE_BASE,
    :onelevel => 1, # ::LDAP::LDAP_SCOPE_ONELEVEL,
    :subtree  => 2  # ::LDAP::LDAP_SCOPE_SUBTREE
  }

  class Error < ::RuntimeError #:nodoc:
  end

  class RecordNotFound < Error
  end

  # Constructs a deep copy of a set of LDAP attributes, normalizing them to
  # arrays as appropriate.  The returned hash has a default value of [].
  def self.clone_ldap_hash(attributes)
    hash = Hash.new {|h,k| h[k] = [] }
    attributes.each do |k,v|
      k = k.kind_of?(Symbol) ?  k.to_s.gsub('_','-') : k.dup
      # LDAP::DN objects have a special to_a method
      if v.kind_of?(LDAP::DN)
        hash[k] = [v.dup]
      else
        hash[k] = Array(v).map {|x| x.dup rescue x}
      end
    end
    hash
  end

  def self.build_hierarchy(connection,base_dn = nil,&block) #:nodoc:
    klass = Class.new(Base)
    klass.send(:connection=, connection)
    klass.base_dn = base_dn
    klass.send(:build_hierarchy)
    klass.instance_eval(&block) if block_given?
    klass
  end

  # The core method of Ldaptor.
  #
  #   $conn = LDAP::Conn.new("mycompany.com")
  #   $conn.bind("CN=Name\\, My,DC=mycompany,DC=com","password")
  #
  #   class MyCompany < Ldaptor::Namespace($conn)
  #   end
  #
  #   me = MyCompany.search(:filter => {:cn => "Name, My"})
  def self.Namespace(connection, base_dn = nil)
    klass = Class.new(Base)
    klass.send(:connection=, connection)
    klass.base_dn = base_dn
    klass.instance_variable_set(:@parent,  true)
    klass
  end

  module ObjectClassMethods
    attr_reader :oid, :desc, :sup
    %w(obsolete abstract structural auxiliary).each do |attr|
      class_eval("def #{attr}?; !! @#{attr}; end")
    end
    def names
      Array(@name)
    end

    def instantiate(attributes, namespace = nil)
      if klass = @subclasses.to_a.find {|c| attributes["objectClass"].to_a.include?(c.object_class)}
        return klass.send(:instantiate,attributes)
      elsif klass = self.namespace.const_get(attributes["objectClass"].last.to_s.ldapitalize(true)) rescue nil
        if klass != self
          return klass.send(:instantiate,attributes)
        end
      end
      obj = allocate
      obj.instance_variable_set(:@dn,Array(attributes.delete('dn')).first)
      obj.instance_variable_set(:@original_attributes,attributes)
      obj.instance_variable_set(:@attributes,Ldaptor.clone_ldap_hash(attributes))
      obj.instance_variable_set(:@namespace, namespace || @namespace)
      obj
    end
    protected :instantiate

    def has_attribute?(attribute)
      attribute = LDAP.escape(attribute)
      may.include?(attribute) || must.include?(attribute)
    end

    def create_accessors
      (may(false) + must(false)).each do |attr|
        method = attr.to_s.tr_s('-_','_-')
        define_method("#{method}") { read_attribute(attr) }
        unless namespace.adapter.attribute_types[attr].no_user_modification?
          define_method("#{method}="){ |value| write_attribute(attr,value) }
        end
      end
    end

    def ldap_ancestors
      ancestors.select {|o| o.respond_to?(:oid) && o.oid }
    end

    def namespace
      @namespace || ancestors.detect {|o| o.respond_to?(:oid) && o.oid.nil? }
    end

    def may(all = true)
      if all
        nott = []
        ldap_ancestors.inject([]) do |memo,klass|
          memo |= Array(klass.may(false))
          nott |= Array(klass.must(false))
          if dit = klass.dit_content_rule
            memo |= Array(dit.may)
            nott |= Array(dit.not)
            # Array(dit.aux).each do |aux|
            # memo |= self.namespace.const_get(aux.ldapitalize(true)).may(false)
            # end
          end
          memo - nott
        end
      else
        Array(@may)
      end
    end

    def must(all = true)
      if all
        ldap_ancestors.inject([]) do |memo,klass|
          memo |= Array(klass.must(false))
          if dit = klass.dit_content_rule
            memo |= Array(dit.must)
            # Array(dit.aux).each do |aux|
            # memo |= self.namespace.const_get(aux.ldapitalize(true)).must(false)
            # end
          end
          memo
        end.flatten.uniq
      else
        Array(@must)
      end
    end

    def aux
      if dit_content_rule
        Array(dit_content_rule.aux)
      else
        []
      end
    end

    def attributes(all = true)
      may(all) + must(all)
    end

    def dit_content_rule
      namespace.adapter.dit_content_rules[oid]
    end

    def object_class
      @object_class || names.first
    end

    def object_classes
      ldap_ancestors.map {|a| a.object_class}.compact.reverse.uniq
    end

    alias objectClass object_classes
  end

  # When a new Ldaptor::Namespace is created, a Ruby class hierarchy is
  # contructed that mirrors the server's object classes.  Ldaptor::Object
  # serves as the base class for this hierarchy.
  class Object
    extend ObjectClassMethods

    def self.inherited(subclass) #:nodoc:
      @subclasses ||= []
      @subclasses << subclass
    end

    def initialize(data = {})
      raise TypeError, "abstract class initialized", caller if self.class.oid.nil? || self.class.abstract?
      @attributes = Ldaptor.clone_ldap_hash({'objectClass' => self.class.object_classes}.merge(data))
      if dn = Array(@attributes.delete('dn')).first
        @dn = LDAP::DN(dn,self)
        (@dn.to_a.first||{}).each do |k,v|
          @attributes[k.to_s.downcase] |= [v]
        end
      end
    end

    # The objects distinguished name.
    def dn
      LDAP::DN(@dn,self) if @dn
    end

    # The first (relative) component of the distinguished name.
    def rdn
      dn && dn.rdn
    end

    def /(*args)
      search(:base => dn.send(:/,*args), :scope => :base, :limit => true)
    end

    # The parent object containing this one.
    def parent
      search(:base => LDAP::DN(dn.parent), :scope => :base, :limit => true)
    end

    def children(type = nil, name = nil)
      if name && name != :*
        search(:base => dn/{type => name}, :scope => :base).first
      elsif type
        search(:filter => {type => :*}, :scope => :onelevel)
      else
        search(:scope => :onelevel)
      end
    end

    # A link back to the namespace.
    def namespace
      @namespace || self.class.namespace
    end

    def adapter
      self.class.namespace.adapter
    end

    def inspect
      str = "#<#{self.class} #{dn}"
      @attributes.each do |k,values|
        s = (values.size == 1 ? "" : "s")
        at = adapter.attribute_types[k]
        if at && at.syntax_object && !at.syntax_object.x_not_human_readable? && at.syntax_object.desc != "Octet String"
          str << " " << k << ": " << values.inspect
        else
          str << " " << k << ": "
          if !at
            str << "(unknown attribute)"
          elsif !at.syntax_object
            str << "(unknown type)"
          else
            str << "(" << values.size.to_s << " binary value" << s << ")"
          end
        end
      end
      # @attributes.reject {|k,v| v.any? {|x| x =~ /[\000-\037]/}}.inspect
      str << ">"
    end

    def read_attribute(key)
      key = LDAP.escape(key)
      values = @attributes[key] || @attributes[key.downcase]
      return nil if values.nil?
      at = adapter.attribute_types[key]
      unless at
        warn "Warning: unknown attribute type for #{key}"
        return values
      end
      if syn = SYNTAXES[at.syntax_oid]
        if at.syntax_oid == ::LDAP::DN::OID # DN
          values = values.map do |value|
            ::LDAP::DN(value,self)
          end
        else
          parser = at.syntax_object
          values = values.map do |value|
            parser.parse(value)
          end
        end
      else
        warn "Warning: unknown syntax #{at.syntax_oid} for attribute type #{Array(at.name).first}"
      end
      if at.single_value?
        values.first
      else
        values
      end
    end
    protected :read_attribute

    # For testing
    def read_attributes
      attributes.keys.inject({}) do |hash,key|
        hash[key] = read_attribute(key)
        hash
      end
    end

    def write_attribute(key,values)
      key = LDAP.escape(key)
      at = adapter.attribute_types[key]
      unless at
        warn "Warning: unknown attribute type for #{key}"
        @attributes[key] = Array(values)
        return values
      end
      if at.no_user_modification?
        raise Error, "read-only value", caller
      end
      if at.single_value?
        values = Array(values)
      end
      raise TypeError, "array expected", caller unless values.kind_of?(Array)
      if must.include?(key) && values.empty?
        raise TypeError, "value required", caller
      end
      if syn = SYNTAXES[at.syntax_oid]
        if at.syntax_oid == LDAP::DN::OID
          values = values.map do |value|
            value.respond_to?(:dn) ? value.dn : value
          end
        else
          parser = at.syntax_object
          values = values.map do |value|
            parser.format(value)
          end
        end
      else
        warn "Warning: unknown syntax #{at.syntax_oid} for attribute type #{Array(at.name).first}"
      end
      @attributes[key] = values
    end
    protected :write_attribute

    attr_reader :attributes
    def attribute_names
      attributes.keys
    end

    def ldap_ancestors
      self.class.ldap_ancestors | objectClass.map {|c| self.namespace.const_get(c.ldapitalize(true))}
    end

    def aux
      objectClass.map {|c| self.namespace.const_get(c.ldapitalize(true))} - self.class.ldap_ancestors
    end

    def must(all = true)
      return self.class.must(all) + aux.map {|a|a.must(false)}.flatten
    end

    def may(all = true)
      return self.class.may(all)  + aux.map {|a|a.may(false) + a.must(false)}.flatten
    end

    def may_must(attribute)
      attribute = attribute.to_s
      if must.include?(attribute)
        :must
      elsif may.include?(attribute)
        :may
      end
    end

    def method_missing(method,*args,&block)
      attribute = LDAP.escape(method)
      method = method.to_s
      if attribute[-1] == ?=
        attribute.chop!
        if may_must(attribute)
          return write_attribute(attribute,*args,&block)
        end
      elsif args.size == 1
        return children(method,*args,&block)
      elsif may_must(attribute)
        return read_attribute(attribute,*args,&block)
      end
      super(method.to_sym,*args,&block)
      # Does not work
      extensions = self.class.const_get("Extensions") rescue nil
      if extensions
        self["objectClass"].reverse.each do |oc|
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

    def [](*values)
      if !values.empty? && values.all? {|v| v.kind_of?(Hash)}
        return search(:base => dn[*values], :scope => :base).first
      end
      raise ArgumentError unless values.size == 1
      value = values.first
      case value
      when /\(.*=/, LDAP::Filter
        search(:filter => value, :scope => :onelevel)
      when /=/, Array
        search(:base => dn[*values], :scope => :base).first
      else read_attribute(value)
      end
    end

    def search(options)
      self.namespace.search({:base => dn}.merge(options))
    end

    def save
      if @original_attributes
        updates = @attributes.reject do |k,v|
          @original_attributes[k] == v
        end
        adapter.modify(dn,updates) unless updates.empty?
      else
        adapter.add(dn, @attributes)
      end
      @original_attributes = @attributes
      @attributes = Ldaptor.clone_ldap_hash(@original_attributes)
      self
    end

    def destroy
      adapter.delete(dn)
      freeze
    end

    def reload
      new = search(:scope => :base).first
      @original_attributes = new.instance_variable_get(:@original_attributes)
      @attributes          = new.instance_variable_get(:@attributes)
      self
    end

    def respond_to?(method)
      super(method) || (may + must + (may+must).map {|x| "#{x}="}).include?(method.to_s)
    end

    def rename(new_rdn)
      # TODO: how is new_rdn escaped?
      adapter.rename(dn,LDAP::DN([new_rdn]),true)
      @dn = dn.parent/new_rdn
    end
  end

  class Base

    class << self

      private
      def inherited(subclass)
        # Namespace
        if @parent
          subclass.send(:build_hierarchy)
        end
        super
      end

      def build_hierarchy
        klasses = adapter.object_classes.values.uniq
        hash = klasses.inject(Hash.new {|h,k|h[k]=[]}) do |hash,k|
          hash[k.sup] << k; hash
        end
        add_constants(hash,Ldaptor::Object)
        self.base_dn ||= adapter.server_default_base_dn
        nil
      end

      def add_constants(klasses,superclass)
        (superclass.names.empty? ? [nil] : superclass.names).each do |myname|
          klasses[myname].each do |sub|
            klass = Class.new(superclass)
            %w(oid name desc sup must may).each do |prop|
              klass.instance_variable_set("@#{prop}", sub.send(prop))
            end
            %w(obsolete abstract structural auxiliary).each do |prop|
              klass.instance_variable_set("@#{prop}", sub.send("#{prop}?"))
            end
            klass.instance_variable_set(:@namespace, self)
            Array(sub.name).each do |name|
              self.const_set(name.ldapitalize(true), klass)
            end
            klass.send(:create_accessors)
            add_constants(klasses, klass)
          end
        end
      end

      def self.inheritable_reader(*names)
        names.each do |name|
          define_method name do
            val = instance_variable_get("@#{name}")
            return val unless val.nil?
            return superclass.send(name) if superclass.respond_to?(name)
          end
        end
      end

      def connection=(options)
        @adapter = Ldaptor::Adapters.for(options)
      end

      public
      inheritable_reader :connection, :base_dn, :adapter
      def base_dn=(dn)
        @base_dn = LDAP::DN(dn,self)
      end
      alias dn base_dn

      def /(*args)
        find(base_dn.send(:/,*args))
      end

      def [](*args)
        if args.empty?
          find(base_dn)
        else
          find(base_dn[*args])
        end
      end

      def *(filter)
        search(:filter => filter, :scope => :onelevel)
      end
      def **(filter)
        search(:filter => filter, :scope => :subtree)
      end

      private

      def search_options(options = {})
        options = options.dup
        if options[:attributes].respond_to?(:to_ary)
          options[:attributes] = options[:attributes].map {|x| LDAP.escape(x)}
        elsif options[:attributes]
          options[:attributes] = LDAP.escape(options[:attributes])
        end
        options[:instantiate] = true unless options.has_key?(:instantiate)
        options.delete(:attributes_only) if options[:instantiate]
        options[:base] = (options[:base] || options[:base_dn] || base_dn).to_s
        options
      end

      def find_one(dn,options)
        objects = search(options.merge(:base => dn, :scope => :base))
        unless objects.size == 1
          raise RecordNotFound, "record not found for #{dn}", caller
        end
        objects.first
      end

      public
      def find(dn,options = {})
        case dn
        when :all   then search(options)
        when :first then search(options.merge(:limit => true))
        when Array  then dn.map {|d| find_one(d,options)}
        else             find_one(dn,options)
        end
      end

      def search(options = {},&block)
        ary = []
        one_attribute = options[:attributes]
        if one_attribute.respond_to?(:to_ary)
          one_attribute = nil
        end
        options = search_options(options)
        if options[:limit] == true
          options[:limit] = 1
          first = true
        end
        adapter.search(options) do |entry|
          if options[:instantiate]
            klass = const_get("Top")
            entry = klass.send(:instantiate,entry,self)
          end
          entry = entry[LDAP.escape(one_attribute)] if one_attribute
          ary << entry
          block.call(entry) if block_given?
          return entry if first == true
          return ary   if options[:limit] == ary.size
        end
        first ? ary.first : ary
      end

    end

  end

end

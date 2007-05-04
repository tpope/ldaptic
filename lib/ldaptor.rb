#!/usr/bin/ruby
# $Id$
# -*- ruby -*- vim:set ft=ruby et sw=2 sts=2:

require 'ldaptor/core_ext'
require 'ldap/dn'
require 'ldap/filter'
require 'ldap'
require 'ldap/control'
require 'ldaptor/schema'
require 'ldaptor/syntaxes'

module Ldaptor

  SCOPES = {
    :base     => ::LDAP::LDAP_SCOPE_BASE,     # 0
    :onelevel => ::LDAP::LDAP_SCOPE_ONELEVEL, # 1
    :subtree  => ::LDAP::LDAP_SCOPE_SUBTREE   # 2
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

    def self.clone_ldap_hash(attributes)
      hash = Hash.new {|h,k| h[k] = [] }
      attributes.each do |k,v|
        hash[k.kind_of?(Symbol) ?  k.to_s.gsub('_','-') : k.dup] = Array(v).map {|x| x.dup rescue x}
      end
      hash
    end


    def initialize(data = {})
      raise TypeError, "abstract class initialized", caller if self.class.name.nil? || self.class.abstract?
      @attributes = self.class.clone_ldap_hash({'objectClass' => self.class.object_classes}.merge(data))
      if @dn = @attributes.delete('dn').first
        @dn = LDAP::DN(@dn,self)
      end
    end

    def dn
      LDAP::DN(@dn || @attributes['dn'].first)
    end

    def rdn
      dn && LDAP::DN(dn.to_a.first(1))
    end

    def /(*args)
      search(:base => dn.send(:/,*args), :scope => :base).first
    end

    def parent
      search(:base => LDAP::DN(dn.to_a[1..-1]))
    end

    def children(type = nil, name = nil)
      if name && name != :*
        search(:base => dn/{type => name}, :scope => :base).first
      elsif type
        search(:filter => {type => :*}, :scope => :onlevel)
      else
        search(:scope => :onelevel)
      end
    end

    def connection
      self.class.connection
    end

    def inspect
      str = "#<#{self.class} #{dn}"
      @attributes.each do |k,values|
        s = (values.size == 1 ? "" : "s")
        at = self.class.attribute_types[k]
        if at.syntax_object && !at.syntax_object.x_not_human_readable? && at.syntax_object.desc != "Octet String"
          str << " " << k << ": " << values.inspect
        else
          str << " " << k << ": "
          if !at.syntax_object
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
      values = @attributes[key]
      return nil if values.nil?
      at = self.class.attribute_types[key]
      unless at
        warn "Warning: unknown attribute type for #{key}"
        return values
      end
      if syn = SYNTAXES[at.syntax_oid]
        if at.syntax_oid == '1.3.6.1.4.1.1466.115.121.1.12' # DN
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

    # For testing
    def read_attributes
      attributes.keys.inject({}) do |hash,key|
        hash[key] = read_attribute(key)
        hash
      end
    end

    def write_attribute(key,values)
      key = LDAP.escape(key)
      at = self.class.attribute_types[key]
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
        if at.syntax_oid == '1.3.6.1.4.1.1466.115.121.1.12' # DN
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

    attr_reader :attributes

    def must(all = true)
      return self.class.must(all)
    end

    def may(all = true)
      # TODO: account for AUX
      return self.class.may(all)

      may = []
      self["objectClass"].reverse.each do |oc|
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
      if must.include?(attribute)
        :must
      elsif may.include?(attribute)
        :may
      end
    end

    def method_missing(method,*args,&block)
      attribute = LDAP.escape(method)
      method = method.to_s
      if attribute[-1] == ?= && self.class.has_attribute?(attribute[0..-2])
        attribute.chop!
        write_attribute(attribute,*args,&block)
      elsif args.size == 1
        children(method,*args,&block)
      elsif self.class.has_attribute?(attribute)
        read_attribute(attribute,*args,&block)
      else
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
      self.class.root.search({:base => dn}.merge(options))
    end

    def save
      if @original_attributes
        updates = @attributes.reject do |k,v|
          @original_attributes[k] == v
        end
        connection.modify(dn,updates) unless updates.empty?
      else
        connection.add(dn, @attributes)
      end
      @original_attributes = @attributes
      @attributes = self.class.clone_ldap_hash(@original_attributes)
      self
    end

    def rename(new_rdn)
      # TODO: how is new_rdn escaped?
      connection.modrdn(dn,new_rdn,true)
      @dn = LDAP::DN([new_rdn,dn.to_a[1..-1]].join(","),self)
    end

    class << self

      def has_attribute?(attribute)
        attribute = LDAP.escape(attribute)
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
      def base_dn=(dn)
        @base_dn = LDAP::DN(dn)
      end

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
          Array(@may)
        end
      end

      def must(all = true)
        if all
          ldap_ancestors.collect do |klass|
            Array(klass.must(false))
          end.flatten.uniq
        else
          Array(@must)
        end
      end

      def schema
        @@schema ||= connection.schema
      end

      def attributes(all = true)
        may(all) + must(all)
      end

      def attribute_types
        @@attribute_types ||= schema["attributeTypes"].inject({}) do |hash,val|
          at = Ldaptor::Schema::AttributeType.new(val)
          hash[at.oid] = at
          Array(at.name).each do |name|
            hash[name] = at
          end
          hash
        end
        @@attribute_types
      end

      def object_class
        @object_class || Array(@name).first
      end

      def object_classes
        ldap_ancestors.map {|a| a.object_class}.compact.reverse.uniq
      end

      alias objectClass object_classes

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
          Ldaptor::Schema::ObjectClass.new(k)
        end.compact
        add_constants(self,klasses,self)
        self.base_dn ||= server_default_base_dn
        nil
      end

      def server_default_base_dn
        result = search_raw(:base => "", :scope => :base, :attributes => %w(defaultNamingContext namingContexts)).first rescue nil
        if result
           result["defaultNamingContext"].to_a.first || result["namingContexts"].to_a.first
        end
      end

      def add_constants(mod,klasses,superclass)
        klasses.each do |sub|
          if Array(superclass.name).include?(sub.sup) || superclass.name == nil && sub.sup == nil
            klass = Class.new(superclass)
            %w(oid name desc sup must may).each do |prop|
              klass.instance_variable_set("@#{prop}", sub.send(prop))
            end
            %w(obsolete abstract structural auxiliary).each do |prop|
              klass.instance_variable_set("@#{prop}", sub.send("#{prop}?"))
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
        obj.instance_variable_set(:@dn,attributes.delete('dn').first)
        obj.instance_variable_set(:@original_attributes,attributes)
        obj.instance_variable_set(:@attributes,clone_ldap_hash(attributes))
        obj
      end
      protected :instantiate

      def /(*args)
        find(base_dn.send(:/,*args))
      end

      def children(type = nil, name = nil)
        if name && name != :*
          self/{type => name}
        elsif type
          search(:filter => {type => :*}, :scope => :onelevel)
        else
          search(:scope => :onelevel)
        end
      end

      def method_missing(method,*args,&block)
        if args.size == 1
          children(method.to_s.ldapitalize,*args)
        else
          super
        end
      end

      private
      def paged_results_control(cookie = "", size = 126)
        # values above 126 cause problems for slapd, as determined by net/ldap
        ::LDAP::Control.new(
          # ::LDAP::LDAP_CONTROL_PAGEDRESULTS,
          "1.2.840.113556.1.4.319",
          ::LDAP::Control.encode(size,cookie),
          false
        )
      end

      def search_options(options = {})
        options = options.dup
        options[:base] = (options[:base] || options[:base_dn] || base_dn).to_s
        options[:scope] = ::Ldaptor::SCOPES[options[:scope]] || options[:scope] || ::Ldaptor::SCOPES[:subtree]
        if options[:attributes]
          options[:attributes] = Array(options[:attributes]).map {|x| LDAP.escape(x)}
        end
        query = options[:filter]
        query = {:objectClass => :*} if query.nil?
        query = LDAP::Filter(query)
        query &= {:objectClass => object_class} if object_class
        options[:filter] = query
        options
      end

      def search_parameters(options = {})
        options = search_options(options)
        case options[:sort]
        when Proc, Method then s_attr, s_proc = nil, options[:sort]
        else s_attr, s_proc = options[:sort], nil
        end
        [
          options[:base],
          options[:scope],
          options[:filter],
          options[:attributes],
          options[:attributes_only],
          options[:timeout].to_i,
          ((options[:timeout].to_f % 1) * 1e6).round,
          s_attr.to_s,
          s_proc
        ]
      end

      def search_raw(options = {},&block)
        ary = []
        cookie = ""
        while cookie
          ctrl = paged_results_control(cookie)
          connection.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS,[ctrl])
          collect = Proc.new do |entry|
            ary << entry
            block.call(entry) if block_given?
            return ary if ary.size == options[:limit]
          end
          result = connection.search2(*search_parameters(options), &collect)
          ctrl = connection.controls.detect {|c| c.oid == ctrl.oid}
          cookie = ctrl && ctrl.decode.last
          cookie = nil if cookie.to_s.empty?
        end
        ary
      ensure
        connection.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS,[]) rescue nil
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
        when :first then search(options.merge(:limit => 1)).first
        when Array  then dn.map {|d| find_one(d,options)}
        else             find_one(dn,options)
        end
      end

      def search(options)
        search_raw(options.reject {|k,v| k == :attributes_only}).
          map {|r| instantiate(r)}
      end

    end

  end

end

if __FILE__ == $0
  require 'irb'
  IRB.start($0)
end


#!/usr/bin/ruby
# $Id$
# -*- ruby -*- vim:set ft=ruby et sw=2 sts=2:

require 'ldaptor/core_ext'
require 'ldap/dn'
require 'ldap/filter'
# require 'ldap'
require 'ldap/control'
require 'ldaptor/schema'
require 'ldaptor/syntaxes'

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

  def self.clone_ldap_hash(attributes)
    hash = Hash.new {|h,k| h[k] = [] }
    attributes.each do |k,v|
      k = k.kind_of?(Symbol) ?  k.to_s.gsub('_','-') : k.dup
      if v.kind_of?(LDAP::DN)
        hash[k] = [v.dup]
      else
        hash[k] = Array(v).map {|x| x.dup rescue x}
      end
    end
    hash
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
    klass.instance_variable_set(:@oid,  false)
    klass
  end

  class Base

    def initialize(data = {})
      raise TypeError, "abstract class initialized", caller if self.class.oid.nil? || self.class.abstract?
      @attributes = Ldaptor.clone_ldap_hash({'objectClass' => self.class.object_classes}.merge(data))
      if dn = @attributes.delete('dn')
        @dn = LDAP::DN(dn.first,self) if dn.first
      end
    end

    def dn
      LDAP::DN(@dn) if @dn
    end

    def rdn
      dn && LDAP::DN(dn.to_a.first(1)).to_s
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

    def namespace
      self.class.namespace
    end
    def connection
      self.class.connection
    end

    def inspect
      str = "#<#{self.class} #{dn}"
      @attributes.each do |k,values|
        s = (values.size == 1 ? "" : "s")
        at = self.class.attribute_types[k]
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
      self.namespace.search({:base => dn}.merge(options))
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
      @attributes = Ldaptor.clone_ldap_hash(@original_attributes)
      self
    end

    def reload
      new = search(:scope => :base).first
      @original_attributes = new.instance_variable_get(:@original_attributes)
      @attributes          = new.instance_variable_get(:@attributes)
      self
    end

    def respond_to?(method)
      super(method) || (may + must + (may+must).map {|x| "#{a}="}).include?(method.to_s)
    end

    def rename(new_rdn)
      # TODO: how is new_rdn escaped?
      connection.modrdn(dn,new_rdn,true)
      @dn = LDAP::DN([new_rdn,dn.to_a[1..-1]].join(","),self)
    end

    class << self

      def instantiate(attributes, namespace = nil) # ObjectClass
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

      def has_attribute?(attribute) # ObjectClass
        attribute = LDAP.escape(attribute)
        may.include?(attribute) || must.include?(attribute)
      end

      def create_accessors # ObjectClass
        (may(false) + must(false)).each do |attr|
          method = attr.to_s.tr_s('-_','_-')
          define_method("#{method}") { read_attribute(attr) }
          unless attribute_types[attr].no_user_modification?
            define_method("#{method}="){ |value| write_attribute(attr,value) }
          end
        end
      end

      def ldap_ancestors # ObjectClass
        ancestors.select {|o| o.respond_to?(:oid) && o.oid }
      end

      def root # ObjectClass
        @namespace || ancestors.detect {|o| o.respond_to?(:oid) && o.oid.nil? }
      end

      def namespace
        root
      end

      def may(all = true) # ObjectClass
        if all
          nott = []
          ldap_ancestors.inject([]) do |memo,klass|
            memo |= Array(klass.may(false))
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

      def must(all = true) # ObjectClass
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

      def aux # ObjectClass
        if dit_content_rule
          Array(dit_content_rule.aux)
        else
          []
        end
      end

      def attributes(all = true) # ObjectClass
        may(all) + must(all)
      end

      def object_class # ObjectClass
        @object_class || names.first
      end

      def object_classes # ObjectClass
        ldap_ancestors.map {|a| a.object_class}.compact.reverse.uniq
      end

      alias objectClass object_classes # ObjectClass

      def inherited(subclass)
        # ObjectClass
        @subclasses ||= []
        @subclasses << subclass
        # Namespace
        if oid == false
          subclass.send(:build_hierarchy)
        end
        super
      end

      def build_hierarchy # ?????
        raise TypeError, "cannot build hierarchy for a named class", caller if oid
        klasses = raw_schema("objectClasses").to_a.map do |k|
          Ldaptor::Schema::ObjectClass.new(k)
        end.compact
        add_constants(self,klasses,self)
        self.base_dn ||= server_default_base_dn
        nil
      end

      def add_constants(mod,klasses,superclass) # ?????
        klasses.each do |sub|
          if superclass.names.include?(sub.sup) || superclass.names.empty? && sub.sup == nil
            klass = Class.new(superclass)
            %w(oid name desc sup must may).each do |prop|
              klass.instance_variable_set("@#{prop}", sub.send(prop))
            end
            %w(obsolete abstract structural auxiliary).each do |prop|
              klass.instance_variable_set("@#{prop}", sub.send("#{prop}?"))
            end
            klass.instance_variable_set(:@namespace, mod)
            Array(sub.name).each do |name|
              mod.const_set(name.ldapitalize(true), klass)
            end
            klass.send(:create_accessors)
            add_constants(self, klasses, klass)
          end
        end
      end
      private :add_constants

      def self.inheritable_accessor(*names) # Namespace
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
      def base_dn=(dn) # Namespace
        @base_dn = LDAP::DN(dn,self)
      end

      # Namespace
      attr_reader :oid, :desc, :sup
      %w(obsolete abstract structural auxiliary).each do |attr|
        class_eval("def #{attr}?; !! @#{attr}; end")
      end
      def names
        Array(@name)
      end
      # def name
        # warn "name is deprecated, use names.first"
        # return super
        # names.first
      # end

      def root_dse(attrs = nil) # Namespace
        attrs ||= %w[
          objectClass
          subschemaSubentry
          namingContexts
          monitorContext
          altServer
          supportedControl
          supportedExtension
          supportedFeatures
          supportedSASLMechanisms
          supportedLDAPVersion
        ]
        result = search(
          :instantiate => false,
          :base => "",
          :scope => :base,
          :filter => {:objectClass => :*},
          :attributes => attrs,
          :limit => true
        )
      end

      def raw_schema(attrs = nil) # Namespace
        attrs ||= %w[
          objectClass
          objectClasses
          attributeTypes
          matchingRules
          matchingRuleUse
          dITStructureRules
          dITContentRules
          nameForms
          ldapSyntaxes
        ]
        result = search(
          :instantiate => false,
          :base => root_dse('subschemaSubentry'),
          :scope => :base,
          :filter => {:objectClass => "subSchema"},
          :attributes => attrs,
          :limit => true
        )
      end

      def schema # Namespace
        instantiate(raw_schema,self.namespace)
      end

      def attribute_types # Namespace
        return self.namespace.attribute_types unless self == self.namespace
        @attribute_types ||= raw_schema("attributeTypes").inject({}) do |hash,val|
          at = Ldaptor::Schema::AttributeType.new(val)
          hash[at.oid] = at
          Array(at.name).each do |name|
            hash[name] = at
          end
          hash
        end
        @attribute_types
      end

      def dit_content_rules # Namespace
        return self.namespace.dit_content_rules unless self == self.namespace
        @dit_content_rules ||= raw_schema("dITContentRules").inject({}) do |hash,val|
          dit = Ldaptor::Schema::DITContentRule.new(val)
          hash[dit.oid] = dit
          Array(dit.name).each do |name|
            hash[name] = dit
          end
          hash
        end
      end

      def dit_content_rule # Namespace
        dit_content_rules[oid]
      end

      def server_default_base_dn # Namespace
        result = root_dse(%w(defaultNamingContext namingContexts))
        if result
          result["defaultNamingContext"].to_a.first ||
            result["namingContexts"].to_a.first
        end
      end

      def /(*args) # Namespace
        find(base_dn.send(:/,*args))
      end

      def [](*args) # Namespace
        if args.empty?
          find(base_dn)
        else
          find(base_dn[*args])
        end
      end

      def *(filter) # Namespace
        search(:filter => filter, :scope => :onelevel)
      end
      def **(filter) # Namespace
        search(:filter => filter, :scope => :subtree)
      end

      private
      def paged_results_control(cookie = "", size = 126) # Namespace
        # values above 126 cause problems for slapd, as determined by net/ldap
        ::LDAP::Control.new(
          # ::LDAP::LDAP_CONTROL_PAGEDRESULTS,
          "1.2.840.113556.1.4.319",
          ::LDAP::Control.encode(size,cookie),
          false
        )
      end

      def search_options(options = {}) # Namespace
        options = options.dup
        options[:instantiate] = true unless options.has_key?(:instantiate)
        options.delete(:attributes_only) if options[:instantiate]
        options[:base] = (options[:base] || options[:base_dn] || base_dn).to_s
        options[:scope] = ::Ldaptor::SCOPES[options[:scope]] || options[:scope] || ::Ldaptor::SCOPES[:subtree]
        if options[:attributes].respond_to?(:to_ary)
          options[:attributes] = options[:attributes].map {|x| LDAP.escape(x)}
        elsif options[:attributes]
          options[:attributes] = LDAP.escape(options[:attributes])
        end
        query = options[:filter]
        query = {:objectClass => :*} if query.nil?
        query = LDAP::Filter(query)
        query &= {:objectClass => object_class} if object_class
        options[:filter] = query
        options
      end

      def search_parameters(options = {}) # Namespace
        case options[:sort]
        when Proc, Method then s_attr, s_proc = nil, options[:sort]
        else s_attr, s_proc = options[:sort], nil
        end
        [
          options[:base],
          options[:scope],
          options[:filter],
          options[:attributes] && Array(options[:attributes]),
          options[:attributes_only],
          options[:timeout].to_i,
          ((options[:timeout].to_f % 1) * 1e6).round,
          s_attr.to_s,
          s_proc
        ]
      end

      def raw_ldap_search(options = {}, &block) # Namespace
        cookie = ""
        options = search_options(options)
        parameters = search_parameters(options)
        while cookie
          ctrl = paged_results_control(cookie)
          connection.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS,[ctrl])
          result = connection.search2(*parameters, &block)
          ctrl = connection.controls.detect {|c| c.oid == ctrl.oid}
          cookie = ctrl && ctrl.decode.last
          cookie = nil if cookie.to_s.empty?
        end
      ensure
        connection.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS,[]) rescue nil
      end

      def raw_net_ldap_search(options = {}, &block) # Namespace
        connection.search(options.merge(:return_result => false)) do |entry|
          hash = {}
          entry.each do |attr,val|
            attr = case attr.to_s
                   when "dn" then "dn"
                   when "attributetypes" then "attributeTypes"
                   when "subschemasubentry" then "subschemaSubentry"
                   else
                     attribute_types.keys.detect do |x|
                       x.downcase == attr.to_s
                       # break(x.name) if x.names.map {|n|n.downcase}.include?(attr.to_s)
                     end
                   end
            hash[attr.to_s] = val
          end
          block.call(hash)
        end
      end

      def raw_adapter_search(options = {}, &block) # Namespace
        if defined?(::LDAP::Conn) && connection.kind_of?(::LDAP::Conn)
          raw_ldap_search(options,&block)
        elsif defined?(::Net::LDAP) && connection.kind_of?(::Net::LDAP)
          raw_net_ldap_search(options,&block)
        else
          raise "invalid connection"
        end
      end

      def find_one(dn,options) # Namespace
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
        cookie = ""
        options = search_options(options)
        if options[:limit] == true
          options[:limit] = 1
          first = true
        end
        one_attribute = options[:attributes]
        if one_attribute.respond_to?(:to_ary)
          one_attribute = nil
        end
        raw_adapter_search(options) do |entry|
          entry = instantiate(entry,self.namespace) if options[:instantiate]
          entry = entry[one_attribute] if one_attribute
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

if __FILE__ == $0
  require 'irb'
  IRB.start($0)
end


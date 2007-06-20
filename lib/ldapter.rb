#!/usr/bin/ruby
# $Id$
# -*- ruby -*- vim:set ft=ruby et sw=2 sts=2:

require 'ldapter/core_ext'
require 'ldap/dn'
require 'ldap/filter'
require 'ldapter/errors'
require 'ldapter/schema'
require 'ldapter/syntaxes'
require 'ldapter/adapters'
require 'ldapter/object'

module Ldapter

  SCOPES = {
    :base     => 0, # ::LDAP::LDAP_SCOPE_BASE,
    :onelevel => 1, # ::LDAP::LDAP_SCOPE_ONELEVEL,
    :subtree  => 2  # ::LDAP::LDAP_SCOPE_SUBTREE
  }

  # Constructs a deep copy of a set of LDAP attributes, normalizing them to
  # arrays as appropriate.  The returned hash has a default value of [].
  def self.clone_ldap_hash(attributes) #:nodoc:
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

  def self.build_hierarchy(options,&block) #:nodoc:
    klass = Class.new(Base)
    klass.send(:instantiate_adapter, options)
    klass.send(:build_hierarchy)
    klass.instance_eval(&block) if block_given?
    klass
  end

  # The core constructor of Ldapter.  This method returns an anonymous class
  # which can then be inherited from.
  #
  #   options = {
  #     :adapter  => :active_directory,
  #     :host     => "mycompany.com",
  #     :username => "MYCOMPANY\\mylogin",
  #     :password => "mypassword"
  #   }
  #
  #   class MyCompany < Ldapter::Namespace(options)
  #     # This class and many others are created automatically based on
  #     # information from the server.
  #     class User
  #       alias login sAMAccountName
  #     end
  #   end
  #
  #   me = MyCompany.search(:filter => {:cn => "Name, My"}).first
  #   puts me.login
  #
  # Options include
  # * <tt>:adapter</tt>: The LDAP connection adapter to use.
  # * <tt>:base</tt>: The default base DN for searches.  If unspecified, this
  #   is guessed by querying the server.
  # All other options are passed along to the adapter.
  def self.Namespace(options)
    klass = Class.new(Base)
    klass.send(:instantiate_adapter, options)
    klass.instance_variable_set(:@parent,  true)
    klass
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
        klasses = adapter.object_classes.values
        klasses.uniq!
        hash = klasses.inject(Hash.new {|h,k|h[k]=[]}) do |hash,k|
          hash[k.sup] << k; hash
        end
        add_constants(hash, Ldapter::Object)
        self.base_dn ||= adapter.default_base_dn
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

      def instantiate_adapter(options)
        if options.kind_of?(Hash)
          self.base_dn ||= options[:base] || options['base']
        end
        @adapter = Ldapter::Adapters.for(options)
      end

      public
      inheritable_reader :base_dn, :adapter
      def base_dn=(dn)
        @base_dn = LDAP::DN(dn,self)
      end
      alias dn base_dn

      # Verifies the given credentials are authorized to connect to the server,
      # by temborarily binding with them.  Returns a boolean.
      def authenticate(dn, password)
        adapter.authenticate(dn, password)
      end

      # Search for an RDN relative to the base.
      #
      #   class MyCompany < Ldapter::Namespace(:base => "DC=org", ...)
      #   end
      #
      #   (MyCompany/{:dc => "ruby-lang"}).dn #=> "DC=ruby-lang,DC=org"
      def /(*args)
        find(base_dn.send(:/,*args))
      end

      # Like #/, only the search results are cached.
      #
      #   MyCompany[:dc=>"ruby-lang"].bacon = "chunky"
      #   MyCompany[:dc=>"ruby-lang"].bacon #=> "chunky"
      def [](*args)
        if args.empty?
          @self ||= find(base_dn)
        else
          self[][*args]
        end
      end

      def []=(*args) #:nodoc:
        self[].send(:[]=,*args)
      end

      # Does a search with the given filter and a scope of onelevel.
      def *(filter) #:nodoc:
        search(:filter => filter, :scope => :onelevel)
      end
      # Does a search with the given filter and a scope of subtree.
      def **(filter) #:nodoc:
        search(:filter => filter, :scope => :subtree)
      end

      private

      def search_options(options = {})
        options = options.dup

        options[:base] = (options[:base] || dn).to_s

        original_scope = options[:scope]
        options[:scope] ||= :subtree
        if !options[:scope].kind_of?(Integer) && options[:scope].respond_to?(:to_sym)
          options[:scope] = Ldapter::SCOPES[options[:scope].to_sym]
        end
        raise ArgumentError, "invalid scope #{original_scope.inspect}", caller(1) unless Ldapter::SCOPES.values.include?(options[:scope])

        options[:filter] ||= {:objectClass => :*}
        if [Hash, Proc, Method].include?(options[:filter].class)
          options[:filter] = LDAP::Filter(options[:filter])
        end

        if options[:attributes].respond_to?(:to_ary)
          options[:attributes] = options[:attributes].map {|x| LDAP.escape(x)}
        elsif options[:attributes]
          options[:attributes] = [LDAP.escape(options[:attributes])]
        end
        if options[:attributes]
          options[:attributes] |= ["objectClass"]
        end

        options.delete(:attributes_only) if options[:instantiate]
        options[:instantiate] = true unless options.has_key?(:instantiate)

        options
      end

      def find_one(dn,options)
        objects = search(options.merge(:base => dn, :scope => :base, :limit => false))
        unless objects.size == 1
          raise Ldapter::Errors::NoSuchObject, "record not found for #{dn}", caller
        end
        objects.first
      end

      public

      # Find an absolute DN, raising an error when no results are found.
      # Equivalent to
      #   .search(:base => dn, :scope => :base, :limit => true) or raise ...
      def find(dn,options = {})
        case dn
        when :all   then search(options)
        when :first then search(options.merge(:limit => true))
        when Array  then dn.map {|d| find_one(d,options)}
        else             find_one(dn,options)
        end
      end

      # * <tt>:base</tt>: The base DN of the search.  The default is derived
      #   from either the <tt>:base</tt> option of the adapter configuration or
      #   by querying the server.
      # * <tt>:scope</tt>: The scope of the search.  Valid values are
      #   <tt>:base</tt> (find the base only), <tt>:onelevel</tt> (children of
      #   the base), and <tt>:subtree</tt> (the base, children, and all
      #   descendants).  The default is <tt>:subtree</tt>.
      # * <tt>:filter</tt>: A standard LDAP filter.  This can be a string, an
      #   LDAP::Filter object, or parameters for LDAP::Filter().
      # * <tt>:limit</tt>: Maximum number of results to return.  If the value
      #   is a literal +true+, the first item is returned directly (or +nil+ if
      #   nothing was found).  For a literal +false+, an array always returned
      #   (the default).
      # * <tt>:attributes</tt>: Specifies an Array of attributes to return.
      #   When unspecified, all attributes are returned.  If this is not an
      #   Array but rather a String or a Symbol, an array of attributes is
      #   returned rather than an array of objects.
      # * <tt>:instantiate</tt>: If this is false, a raw hash is returned
      #   rather than an Ldapter object.  Combined with a String or Symbol
      #   argument to <tt>:attributes</tt>, a +false+ value here causes the
      #   attribute not to be typecast.
      #
      # Option examples:
      #   # Returns all people.
      #   MyCompany.search(:filter => {:objectClass => "person"})
      #   # Returns an array of strings because givenName is marked as a singular value on this server.
      #   MyCompany.search(:attribute => :givenName)
      #   # Returns an array of arrays of strings.
      #   MyCompany.search(:attribute => :givenName, :instantiate => false)
      #   # Returns the first object found.
      #   MyCompany.search(:limit => true)
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
            entry = klass.instantiate(entry,self)
          end
          entry = entry[LDAP.escape(one_attribute)] if one_attribute
          ary << entry
          block.call(entry) if block_given?
          return entry if first == true
          return ary   if options[:limit] == ary.size
        end
        first ? ary.first : ary
      end

      def root_dse(attrs = nil) #:nodoc:
        search(
          :base => "",
          :scope => :base,
          :attributes => attrs,
          :limit => true,
          :instantiate => false
        )
      end

      def schema(attrs = nil) #:nodoc:
        search(
          :base => root_dse(:subschemaSubentry).first,
          :scope => :base,
          :attributes => attrs,
          :limit => true
        )
      end

    end

  end

end
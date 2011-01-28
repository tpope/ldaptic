module Ldaptic

  # These methods are accessible directly from the Ldaptic object.
  module Methods

    # For duck typing.
    def to_ldaptic
      self
    end

    def build_hierarchy
      klasses = adapter.object_classes.values
      klasses.uniq!
      hash = klasses.inject(Hash.new { |h, k| h[k] = [] }) do |hash, k|
        hash[k.sup] << k; hash
      end
      @object_classes = {}
      add_constants(hash, Ldaptic::Entry)
      nil
    end
    private :build_hierarchy

    def add_constants(klasses, superclass)
      (superclass.names.empty? ? [nil] : superclass.names).each do |myname|
        klasses[myname].each do |sub|
          klass = ::Class.new(superclass)
          %w(oid name desc sup must may).each do |prop|
            klass.instance_variable_set("@#{prop}", sub.send(prop))
          end
          %w(obsolete abstract structural auxiliary).each do |prop|
            klass.instance_variable_set("@#{prop}", sub.send("#{prop}?"))
          end
          klass.instance_variable_set(:@namespace, self)
          @object_classes[sub.oid.tr('-', '_').downcase] = klass
          Array(sub.name).each do |name|
            name = name.tr('-', '_')
            name[0,1] = name[0,1].upcase
            @object_classes[name.downcase] = klass
            const_set(name, klass)
          end
          klass.class_eval { create_accessors }
          add_constants(klasses, klass)
        end
      end
    end
    private :add_constants

    attr_reader :adapter

    # Set a new base DN.  Generally, the base DN should be set when the
    # namespace is created and left unchanged.
    def base=(dn)
      @base = Ldaptic::DN(dn, self)
    end
    # Access the base DN.
    def base
      @base ||= Ldaptic::DN(adapter.default_base_dn, self)
    end
    alias dn base

    def logger
      @logger ||= adapter.logger
    end

    # Find an RDN relative to the base.  This method is experimental.
    #
    #   class L < Ldaptic::Class(:base => "DC=ruby-lang,DC=org", ...)
    #   end
    #
    #   (L/{:cn => "Matz"}).dn #=> "CN=Matz,DC=ruby-lang,DC=org"
    def /(*args)
      find(base.send(:/, *args))
    end

    # Like #/, only the search results are cached.  This method is
    # experimental.
    #
    #   L[:cn=>"Why"].bacon = "chunky"
    #   L[:cn=>"Why"].bacon #=> "chunky"
    #   L[:cn=>"Why"].save
    def [](*args)
      if args.empty?
        @self ||= find(base)
      else
        self[][*args]
      end
    end

    # Like Ldaptic::Entry#[]= for the root node.  Only works for assigning
    # children.  This method is experimental.
    #
    #   MyCompany[:cn=>"New Employee"] = MyCompany::User.new
    def []=(*args) #:nodoc:
      self[].send(:[]=, *args)
    end

    # Clears the cache of children.  This cache is automatically populated
    # when a child is accessed through #[].
    def reload
      if @self
        @self.reload rescue nil
        @self = nil
      end
    end

    def search_options(options = {})
      options = options.dup

      if options[:base].kind_of?(Hash)
        options[:base] = dn/options[:base]
      end
      options[:base] = (options[:base] || dn).to_s

      original_scope = options[:scope]
      options[:scope] ||= :subtree
      if !options[:scope].kind_of?(Integer) && options[:scope].respond_to?(:to_sym)
        options[:scope] = Ldaptic::SCOPES[options[:scope].to_sym]
      end
      Ldaptic::Errors.raise(ArgumentError.new("invalid scope #{original_scope.inspect}")) unless Ldaptic::SCOPES.values.include?(options[:scope])

      options[:filter] ||= "(objectClass=*)"
      if [Hash, Proc, Method, Symbol, Array].include?(options[:filter].class)
        options[:filter] = Ldaptic::Filter(options[:filter])
      end

      if options[:attributes].respond_to?(:to_ary)
        options[:attributes] = options[:attributes].map {|x| Ldaptic.encode(x)}
      elsif options[:attributes]
        options[:attributes] = [Ldaptic.encode(options[:attributes])]
      end
      if options[:attributes]
        options[:attributes] |= ["objectClass"]
      end

      options.delete(:attributes_only) if options[:instantiate]
      options[:instantiate] = true unless options.has_key?(:instantiate)

      options
    end
    private :search_options

    def find_one(dn, options)
      objects = search(options.merge(:base => dn, :scope => :base, :limit => false))
      unless objects.size == 1
        # For a missing DN, the error will be raised automatically.  If the
        # DN does exist but is not returned (e.g., it doesn't match the given
        # filter), we'll simulate it instead.
        Ldaptic::Errors.raise(Ldaptic::Errors::NoSuchObject.new("record not found for #{dn}"))
      end
      objects.first
    end
    private :find_one

    # A potential replacement or addition to find.  Does not handle array
    # arguments or do any of the active record monkey business.
    def fetch(dn = self.dn, options = {}) #:nodoc:
      find_one(dn, options)
    end

    # Find an absolute DN, raising an error when no results are found.
    #   L.find("CN=Matz,DC=ruby-lang,DC=org")
    # A hash is treated as an RDN relative to the default base.
    #   L.find(:cn=>"Matz")
    # Equivalent to
    #   L.search(:base => dn, :scope => :base, :limit => true) or raise ...
    def find(dn = self.dn, options = {})
      # Some misguided attempts to emulate active record.
      case dn
      when :all   then search({:limit => false}.merge(options))
      when :first then first(options)
      when Array  then dn.map {|d| fetch(d, options)}
      else             fetch(dn, options)
      end
    end

    # Like #search, but only returns one entry.
    def first(options = {})
      search(options.merge(:limit => true))
    end

    # This is the core method for LDAP searching.
    # * <tt>:base</tt>: The base DN of the search.  The default is derived
    #   from either the <tt>:base</tt> option of the adapter configuration or
    #   by querying the server.
    # * <tt>:scope</tt>: The scope of the search.  Valid values are
    #   <tt>:base</tt> (find the base only), <tt>:onelevel</tt> (children of
    #   the base), and <tt>:subtree</tt> (the base, children, and all
    #   descendants).  The default is <tt>:subtree</tt>.
    # * <tt>:filter</tt>: A standard LDAP filter.  This can be a string, an
    #   Ldaptic::Filter object, or parameters for Ldaptic::Filter().
    # * <tt>:limit</tt>: Maximum number of results to return.  If the value
    #   is a literal +true+, the first item is returned directly (or +nil+ if
    #   nothing was found).  For a literal +false+, an array always returned
    #   (the default).
    # * <tt>:attributes</tt>: Specifies an Array of attributes to return.
    #   When unspecified, all attributes are returned.  If this is not an
    #   Array but rather a String or a Symbol, an array of attributes is
    #   returned rather than an array of objects.
    # * <tt>:instantiate</tt>: If this is false, a raw hash is returned
    #   rather than an Ldaptic object.  Combined with a String or Symbol
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
    def search(options = {}, &block)
      logger.debug("#{inspect}.search(#{options.inspect[1..-2]})")
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
          entry = klass.instantiate(entry)
        end
        if one_attribute
          entry = entry[Ldaptic.encode(one_attribute)]
          entry = entry.one if entry.respond_to?(:one)
        end
        ary << entry
        block.call(entry) if block_given?
        return entry if first == true
        return ary   if options[:limit] == ary.size
      end
      first ? ary.first : ary
    end

    def normalize_attributes(attributes)
      attributes.inject({}) do |h, (k, v)|
        h.update(Ldaptic.encode(k) => v.respond_to?(:before_type_cast) ? v.before_type_cast : Array(v))
      end
    end
    private :normalize_attributes

    # Performs an LDAP add.
    def add(dn, attributes)
      attributes = normalize_attributes(attributes)
      log_dispatch(:add, dn, attributes)
      adapter.add(dn, attributes)
    end

    # Performs an LDAP modify.
    def modify(dn, attributes)
      if attributes.kind_of?(Hash)
        attributes = normalize_attributes(attributes)
      else
        attributes = attributes.map do |(action, key, values)|
          [action, Ldaptic.encode(key), values.respond_to?(:before_type_cast) ? values.before_type_cast : Array(values)]
        end
      end
      log_dispatch(:modify, dn, attributes)
      adapter.modify(dn, attributes) unless attributes.empty?
    end

    # Performs an LDAP delete.
    def delete(dn)
      log_dispatch(:delete, dn)
      adapter.delete(dn)
    end

    # Performs an LDAP modrdn.
    def rename(dn, new_rdn, delete_old, *args)
      log_dispatch(:delete, dn, new_rdn, delete_old, *args)
      adapter.rename(dn, new_rdn.to_str, delete_old, *args)
    end

    # Performs an LDAP compare.
    def compare(dn, key, value)
      log_dispatch(:compare, dn, key, value)
      adapter.compare(dn, Ldaptic.encode(key), Ldaptic.encode(value))
    end

    def dit_content_rule(oid)
      adapter.dit_content_rules[oid]
    end

    # Retrieves attributes from the Root DSE.  If +attrs+ is an array, a hash
    # is returned keyed on the attribute.
    #
    #   L.root_dse(:subschemaSubentry) #=> ["cn=Subschema"]
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
        :base => Array(root_dse(:subschemaSubentry)).first,
        :scope => :base,
        :attributes => attrs,
        :limit => true
      )
    end

    # Returns the object class for a given name or OID.
    #
    #   L.object_class("top") #=> L::Top
    def object_class(klass)
      @object_classes[klass.to_s.tr('-', '_').downcase]
    end

    # Returns an Ldaptic::Schema::AttibuteType object encapsulating server
    # provided information about an attribute type.
    #
    #   L.attribute_type(:cn).desc #=> "RFC2256: common name..."
    def attribute_type(attribute)
      adapter.attribute_type(Ldaptic.encode(attribute))
    end
    # Returns an Ldaptic::Schema::LdapSyntax object encapsulating server
    # provided information about the syntax of an attribute.
    #
    #    L.attribute_syntax(:cn).desc #=> "Directory String"
    def attribute_syntax(attribute)
      type   = attribute_type(attribute)
      syntax = nil
      until type.nil? || syntax = type.syntax
        type = attribute_type(type.sup)
      end
      syntax
    end

    # Verifies the given credentials are authorized to connect to the server
    # by temporarily binding with them.  Returns a boolean.
    def authenticate(dn, password)
      adapter.authenticate(dn, password)
    end

    # Delegated to from Ldaptic::Entry for Active Model compliance.
    def model_name
      if defined?(ActiveSupport::ModelName)
        ActiveSupport::ModelName.new(name)
      else
        ActiveModel::Name.new(self)
      end
    end

    # Convenience method for use with Rails.  Allows the singleton to be used
    # as a before filter, an after filter, or an around filter.
    #
    #   class ApplicationController < ActionController::Base
    #     prepend_around_filter MyCompany
    #   end
    #
    # When invoked, the filter clears cached children.  This operation is
    # cheap and quite necessary if you care to avoid stale data.
    def filter(controller = nil)
      if controller
        reload
        if block_given?
          begin
            yield
          ensure
            reload
          end
        end
      else
        yield if block_given?
      end
      self
    end

    def log_dispatch(method, *args)
      if logger.debug?
        logger.debug("#{inspect}.#{method}(#{args.inspect[1..-2]})")
      end
    end

  end

end

module Ldapter

  # These methods are accessible directly from the Ldapter object.
  module Methods

    # For duck typing.
    def to_ldapter
      self
    end

    private

      def build_hierarchy
        klasses = adapter.object_classes.values
        klasses.uniq!
        hash = klasses.inject(Hash.new {|h,k|h[k]=[]}) do |hash,k|
          hash[k.sup] << k; hash
        end
        @object_classes = {}
        add_constants(hash, Ldapter::Entry)
        nil
      end

      def add_constants(klasses,superclass)
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
            @object_classes[sub.oid.tr('-','_').downcase] = klass
            Array(sub.name).each do |name|
              name = name.ldapitalize(true)
              @object_classes[name.downcase] = klass
              const_set(name, klass)
            end
            klass.send(:create_accessors)
            add_constants(klasses, klass)
          end
        end
      end

    public
      attr_reader :adapter

      def base=(dn)
        @base = LDAP::DN(dn,self)
      end
      def base
        @base ||= LDAP::DN(adapter.default_base_dn,self)
      end
      alias dn base

      def logger
        @logger ||= adapter.logger
      end

      # Search for an RDN relative to the base.
      #
      #   class L < Ldapter::Class(:base => "DC=org", ...)
      #   end
      #
      #   (L/{:dc => "ruby-lang"}).dn #=> "DC=ruby-lang,DC=org"
      def /(*args)
        find(base.send(:/,*args))
      end

      # Like #/, only the search results are cached.
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

      # Like Ldapter::Entry#[]= for the root node.  Only works for assigning
      # children.
      #
      #   MyCompany[:cn=>"New Employee"] = MyCompany::User.new
      def []=(*args) #:nodoc:
        self[].send(:[]=,*args)
      end

      # Clear the cache of children.  This cache is automatically populated
      # when a child is accessed through #[].
      def reload
        if @self
          @self.reload rescue nil
          @self = nil
        end
      end

      # Does a search with the given filter and a scope of onelevel.
      # def *(filter) #:nodoc:
        # search(:filter => filter, :scope => :onelevel)
      # end
      # Does a search with the given filter and a scope of subtree.
      # def **(filter) #:nodoc:
        # search(:filter => filter, :scope => :subtree)
      # end

    private

      def search_options(options = {})
        options = options.dup

        if options[:base].kind_of?(Hash)
          options[:base] = dn/options[:base]
        end
        options[:base] = (options[:base] || dn).to_s

        original_scope = options[:scope]
        options[:scope] ||= :subtree
        if !options[:scope].kind_of?(Integer) && options[:scope].respond_to?(:to_sym)
          options[:scope] = Ldapter::SCOPES[options[:scope].to_sym]
        end
        raise ArgumentError, "invalid scope #{original_scope.inspect}", caller(1) unless Ldapter::SCOPES.values.include?(options[:scope])

        options[:filter] ||= "(objectClass=*)"
        if [Hash, Proc, Method, Symbol].include?(options[:filter].class)
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
      def find(dn = self.dn, options = {})
        case dn
        when :all   then search({:limit => false}.merge(options))
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
            entry = klass.instantiate(entry)
          end
          entry = entry[LDAP.escape(one_attribute)] if one_attribute
          ary << entry
          block.call(entry) if block_given?
          return entry if first == true
          return ary   if options[:limit] == ary.size
        end
        first ? ary.first : ary
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
        @object_classes[klass.to_s.tr('-','_').downcase]
      end

      # Returns an object encapsulating server provided information about an
      # attribute type.
      #
      #   L.attribute_type(:cn).desc #=> "RFC2256: common name..."
      def attribute_type(attribute)
        adapter.attribute_types[LDAP.escape(attribute)]
      end
      # Returns an object encapsulating server provided information about the
      # syntax of an attribute.
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

  end

end

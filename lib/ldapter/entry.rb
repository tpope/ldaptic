require 'ldapter/attribute_set'

module Ldapter

  # When a new Ldapter namespace is created, a Ruby class hierarchy is
  # contructed that mirrors the server's object classes.  Ldapter::Entry
  # serves as the base class for this hierarchy.
  class Entry
    # Constructs a deep copy of a set of LDAP attributes, normalizing them to
    # arrays as appropriate.  The returned hash has a default value of [].
    def self.clone_ldap_hash(attributes) #:nodoc:
      hash = Hash.new #{|h,k| h[k] = [] }
      attributes.each do |k,v|
        k = k.kind_of?(Symbol) ?  k.to_s.tr('_','-') : k.dup
        hash[k] = Array(v).map {|x| x.dup rescue x}
      end
      hash
    end

    class << self
      attr_reader :oid, :desc, :sup
      %w(obsolete abstract structural auxiliary).each do |attr|
        class_eval("def #{attr}?; !! @#{attr}; end")
      end

      def logger
        namespace.logger
      end

      # Returns an array of all names for the object class.  Typically the
      # number of names is one, but it is possible for an object class to have
      # aliases.
      def names
        Array(@name)
      end

      def has_attribute?(attribute)
        attribute = LDAP.escape(attribute)
        may.include?(attribute) || must.include?(attribute)
      end

      def create_accessors #:nodoc:
        (may(false) + must(false)).each do |attr|
          method = attr.to_s.tr_s('-_','_-')
          class_eval(<<-RUBY,__FILE__,__LINE__)
          def #{method}(*args,&block)
            read_attribute('#{attr}',*args,&block)
          end
          def #{method}=(value)
            write_attribute('#{attr}',value)
          end
          RUBY
          # define_method("#{method}") { |*args| read_attribute(attr,*args) }
          # If we skip this check we can delay the attribute type
          # initialization and improve startup speed.
          # unless namespace.attribute_type(attr).no_user_modification?
            # define_method("#{method}="){ |value| write_attribute(attr,value) }
          # end
        end
      end

      # An array of classes that make up the inheritance hierarchy.
      #
      #   L::OrganizationalPerson.ldap_ancestors #=> [L::OrganizationalPerson, L::Person, L::Top]
      def ldap_ancestors
        ancestors.select {|o| o.respond_to?(:oid) && o.oid }
      end

      attr_reader :namespace

      def may(all = true)
        if all
          core = []
          nott = []
          ldap_ancestors.reverse.each do |klass|
            core |= Array(klass.may(false))
            nott |= Array(klass.must(false))
            # if dit = klass.dit_content_rule
              # memo |= Array(dit.may)
              # nott |= Array(dit.not)
            # end
          end
          if dit = dit_content_rule
            core.push(*Array(dit.may))
            core -= Array(dit.must)
            core -= Array(dit.not)
          end
          core -= nott
          core
        else
          Array(@may)
        end
      end

      def must(all = true)
        if all
          core = ldap_ancestors.inject([]) do |memo,klass|
            memo |= Array(klass.must(false))
            # if dit = klass.dit_content_rule
              # memo |= Array(dit.must)
            # end
            memo
          end
          if dit = dit_content_rule
            core.push(*Array(dit.must))
          end
          core
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

      def instantiate(attributes) #:nodoc:
        ocs = attributes["objectClass"].to_a.map {|c| namespace.object_class(c)}
        subclass = (@subclasses.to_a & ocs).detect {|x| !x.auxiliary?}
        if subclass
          return subclass.instantiate(attributes)
        end
        unless structural? || ocs.empty?
          logger.warn("ldapter") { "#{self}: invalid object class for #{attributes.inspect}" }
        end
        obj = allocate
        obj.instance_variable_set(:@dn, ::LDAP::DN(Array(attributes.delete('dn')).first,obj))
        obj.instance_variable_set(:@original_attributes, attributes)
        obj.instance_variable_set(:@attributes, {})
        # obj.instance_variable_set(:@attributes, Ldapter::Entry.clone_ldap_hash(attributes))
        # obj.instance_variable_set(:@namespace, namespace || @namespace)
        obj.instance_eval { common_initializations }
        obj
      end
      # private :instantiate

      protected
      def inherited(subclass) #:nodoc:
        if superclass != Object
          @subclasses ||= []
          @subclasses << subclass
        end
      end

    end

    def initialize(data = {})
      Ldapter::Errors.raise(TypeError.new("abstract class initialized")) if self.class.oid.nil? || self.class.abstract?
      @attributes = {}
      data = data.dup
      if dn = data.delete('dn')||data.delete(:dn)
        dn.first if dn.kind_of?(Array)
        self.dn = dn
      end
      data.each do |key,value|
        write_attribute(key,value)
      end
      # @attributes = Ldapter::Entry.clone_ldap_hash(data)
      @attributes['objectClass'] ||= []
      @attributes['objectClass'].insert(0,*self.class.object_classes).uniq!
      common_initializations
    end


    # A link back to the namespace.
    def namespace
      @namespace || self.class.namespace
    end

    def logger
      self.class.logger
    end

    attr_reader :dn

    # The first (relative) component of the distinguished name.
    def rdn
      dn && dn.rdn
    end

    # The parent object containing this one.
    def parent
      unless @parent
        @parent = search(:base => dn.parent, :scope => :base, :limit => true)
        @parent.instance_variable_get(:@children)[rdn] = self
      end
      @parent
    end

    def inspect
      str = "#<#{self.class.inspect} #{dn}"
      (@original_attributes||{}).merge(@attributes).each do |k,values|
        s = (values.size == 1 ? "" : "s")
        at = namespace.attribute_type(k)
        syntax = namespace.attribute_syntax(k)
        if at && syntax && !syntax.x_not_human_readable? && syntax.desc != "Octet String"
          str << " " << k << ": " << values.inspect
        else
          str << " " << k << ": "
          if !at
            str << "(unknown attribute)"
          elsif !syntax
            str << "(unknown type)"
          else
            str << "(" << values.size.to_s << " binary value" << s << ")"
          end
        end
      end
      # @attributes.reject {|k,v| v.any? {|x| x =~ /[\000-\037]/}}.inspect
      str << ">"
    end

    def to_s
      "#<#{self.class} #{dn}>"
    end

    # Reads an attribute and typecasts it if neccessary.  If the server
    # indicates the attribute is <tt>SINGLE-VALUE</tt>, the sole attribute or
    # +nil+ is returned.  Otherwise, an array is returned.
    #
    # If the argument given is a symbol, underscores are translated into
    # hyphens.  Since #method_missing delegates to this method, method names
    # with underscores map to attributes with hyphens.
    def read_attribute(key, always_array = false, &block)
      key = LDAP.escape(key)
      @attributes[key] ||= ((@original_attributes||{})[key] || []).dup
      values = Ldapter::AttributeSet.new(self, key, @attributes[key])
      single = values.single_value?
      if block_given?
        values = values.map(&block)
      end
      (always_array || !single) ? values : values.first
    end
    protected :read_attribute

    # For testing.
    def read_attributes #:nodoc:
      @original_attributes.merge(@attributes).keys.inject({}) do |hash,key|
        hash[key] = read_attribute(key)
        hash
      end
    end

    # Change an attribute.  This is called by #method_missing and
    # <tt>[]=</tt>.  Exceptions are raised if certain server dictated criteria
    # are violated.  For example, a TypeError is raised if you try to assign
    # multiple values to an attribute marked <tt>SINGLE-VALUE</tt>.
    #
    # Changes are not committed to the server until #save is called.
    def write_attribute(key,values)
      read_attribute(key, true).replace(values)
    end
    protected :write_attribute

    # Note the values are not typecast and thus must be strings.
    def modify_attribute(action, key, *values)
      key = LDAP.escape(key)
      values.flatten!
      @original_attributes[key] ||= []
      virgin   = @original_attributes[key].dup
      original = Ldapter::AttributeSet.new(self, key, @original_attributes[key])
      original.__send__(action, values)
      begin
        namespace.adapter.modify(dn, [[action, key, values]])
      rescue
        @original_attributes[key] = virgin
        raise $!
      end
      if @attributes[key]
        read_attribute(key, true).__send__(action, values)
      end
      self
    end
    private :modify_attribute

    def add!(key, *values) #:nodoc:
      modify_attribute(:add, key, values)
    end

    def replace!(key, *values) #:nodoc:
      modify_attribute(:replace, key, values)
    end

    def delete!(key, *values) #:nodoc:
      modify_attribute(:delete, key, values)
    end

    # attr_reader :attributes
    def attribute_names
      attributes.keys
    end

    def ldap_ancestors
      self.class.ldap_ancestors | objectClass.map {|c|namespace.object_class(c)}
    end

    def aux
      objectClass.map {|c| namespace.object_class(c)} - self.class.ldap_ancestors
    end

    def must(all = true)
      return self.class.must(all) + aux.map {|a|a.must(false)}.flatten
    end

    def may(all = true)
      return self.class.may(all)  + aux.map {|a|a.may(false)}.flatten
    end

    def may_must(attribute)
      attribute = LDAP.escape(attribute)
      if must.include?(attribute)
        :must
      elsif may.include?(attribute)
        :may
      end
    end

    def respond_to?(method) #:nodoc:
      super(method) || (may + must + (may+must).map {|x| "#{x}="}).include?(method.to_s)
    end

    # Delegates to +read_attribute+ or +write_attribute+.
    def method_missing(method,*args,&block)
      attribute = LDAP.escape(method)
      if attribute[-1] == ?=
        attribute.chop!
        if may_must(attribute)
          return write_attribute(attribute,*args,&block)
        end
      elsif attribute[-1] == ??
        unless args.empty?
          raise ArgumentError, "wrong number of arguments (#{args.size} for 0)", caller
        end
        attribute.chop!
        if may_must(attribute)
          return !read_attribute(attribute,true).empty?
        end
      elsif may_must(attribute)
        return read_attribute(attribute,*args,&block)
      end
      super(method,*args,&block)
    end

    # Searches for children.  This is identical to Ldapter::Base#search, only
    # the default base is the current object's DN.
    def search(options,&block)
      if options[:base].kind_of?(Hash)
        options = options.merge(:base => dn/options[:base])
      end
      namespace.search({:base => dn}.merge(options),&block)
    end

    # Searches for a child, given an RDN.
    def /(*args)
      search(:base => dn.send(:/,*args), :scope => :base, :limit => true)
    end

    alias find /

    def fetch(dn = self.dn, options = {}) #:nodoc:
      search({:base => dn}.merge(options))
    end

    # If a Hash or a String containing "=" is given, the argument is treated as
    # an RDN and a search for a child is performed.  +nil+ is returned if no
    # match is found.
    #
    # For a singular String or Symbol argument, that attribute is read with
    # read_attribute.
    def [](key)
      if key.kind_of?(Hash) || key =~ /=/
        cached_child(key)
      else
        read_attribute(key)
      end
    end

    def []=(key, value)
      if key.kind_of?(Hash) || key =~ /=/
        assign_child(key, value)
      else
        write_attribute(key, value)
      end
    end

    # Has the object been saved before?
    def new_entry?
      !@original_attributes
    end

    # For new objects, does an LDAP add.  For existing objects, does an LDAP
    # modify.  This only sends the modified attributes to the server.
    def save
      if @original_attributes
        updates = @attributes.reject do |k,v|
          @original_attributes[k] == v
        end
        namespace.adapter.modify(dn, updates) unless updates.empty?
      else
        namespace.adapter.add(dn, @attributes)
      end
      @original_attributes = (@original_attributes||{}).merge(@attributes)
      # @attributes = Ldapter::Entry.clone_ldap_hash(@original_attributes)
      @attributes = {}
      self
    end

    # Refetches the attributes from the server.
    def reload
      new = search(:scope => :base, :limit => true)
      @original_attributes = new.instance_variable_get(:@original_attributes)
      @attributes          = new.instance_variable_get(:@attributes)
      @dn                  = LDAP::DN(new.dn, self)
      @children            = {}
      self
    end

    # Deletes the object from the server and freezes it locally.
    def delete
      namespace.adapter.delete(dn)
      if @parent
        @parent.instance_variable_get(:@children).delete(rdn)
      end
      freeze
    end

    alias destroy delete

    def rename(new_rdn, delete_old = false)
      old_rdn = rdn
      new_rdn = LDAP::RDN(new_rdn)
      namespace.adapter.rename(dn,new_rdn.to_str,delete_old)
      if delete_old
        old_rdn.each do |k,v|
          [@attributes, @original_attributes].each do |hash|
            hash.delete_if {|k2,v2| k.to_s.downcase == k2.to_s.downcase && v.to_s.downcase == v2.to_s.downcase }
            end
        end
      end
      old_dn = LDAP::DN(@dn,self)
      @dn = nil
      self.dn = old_dn.parent / new_rdn
      write_attributes_from_rdn(rdn, @original_attributes)
      if @parent
        children = @parent.instance_variable_get(:@children)
        if child = children.delete(old_rdn)
          children[new_rdn] = child if child == self
        end
      end
      self
    end

    protected

    def dn=(value)
      if @dn
        Ldapter::Errors.raise(Ldapter::Error.new("can't reassign DN"))
      end
      @dn = ::LDAP::DN(value,self)
      write_attributes_from_rdn(rdn)
    end

    private

    def common_initializations
      @children ||= {}
    end

    def warn(message)
      if logger
        logger.warn('ldapter') { message }
      else
        Kernel.warn message
      end
    end

    def write_attributes_from_rdn(rdn, attributes = @attributes)
      LDAP::RDN(rdn).each do |k,v|
        attributes[k.to_s.downcase] ||= []
        attributes[k.to_s.downcase] |= [v]
      end
    end

    def cached_child(rdn = nil)
      return self if rdn.nil? || rdn.empty?
      rdn = LDAP::RDN(rdn)
      return @children[rdn] if @children.has_key?(rdn)
      begin
        child = search(:base => rdn, :scope => :base, :limit => true)
        child.instance_variable_set(:@parent, self)
        @children[rdn] = child
      rescue Ldapter::Errors::NoSuchObject
      end
    end

    def assign_child(rdn,child)
      unless child.respond_to?(:dn)
        Ldapter::Errors.raise(TypeError.new("#{child.class} cannot be a child"))
      end
      if child.dn
        Ldapter::Errors.raise(Ldapter::Error.new("#{child.class} already has a DN of #{child.dn}"))
      end
      rdn = LDAP::RDN(rdn)
      if cached_child(rdn)
        Ldapter::Errors.raise(Ldapter::Error.new("child #{[rdn,dn].join(",")} already exists"))
      end
      @children[rdn] = child
      child.dn = LDAP::DN(dn/rdn,child)
      child.instance_variable_set(:@parent, self)
    end

  end
end

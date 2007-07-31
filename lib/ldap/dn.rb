require 'ldap/escape'

module LDAP #:nodoc:

  # Instantiate a new LDAP::DN object with the arguments given.  Unlike
  # LDAP::DN.new(dn), this method coerces the first argument to a string,
  # unless it is already a string or an array.  If the first argument is nil,
  # nil is returned.
  def self.DN(dn, source = nil)
    return nil if dn.nil?
    dn = dn.dn if dn.respond_to?(:dn)
    if dn.kind_of?(::LDAP::DN)
      if source
        dn = dn.dup
        dn.source = source
      end
      return dn
    end
    if dn.respond_to?(:to_hash)
      dn = [dn]
    elsif ! dn.respond_to?(:to_ary)
      dn = dn.to_s
    end
    DN.new(dn,source)
  end

  # RFC4512 - Lightweight Directory Access Protocol (LDAP): Directory Information Models
  # RFC4514 - Lightweight Directory Access Protocol (LDAP): String Representation of Distinguished Names
  #
  class DN < ::String

    OID = '1.3.6.1.4.1.1466.115.121.1.12' unless defined? OID
    #   LDAP::DN[{:dc => 'com'},{:dc => 'amazon'}]
    #   => "dc=amazon,dc=com"
    def self.[](*args)
      LDAP::DN(args.reverse)
    end

    attr_accessor :source

    # Create a new LDAP::DN object. dn can either be a string, or an array of
    # pairs.
    #
    #   LDAP::DN([{:cn=>"Thomas, David"},{:dc=>"pragprog"},{:dc=>"com"}])
    #   # => "CN=Thomas\\, David,DC=pragprog,DC=com"
    #
    # The optional second object specifies either an LDAP::Conn object or a
    # Ldapter object to be used to find the DN with #find.
    def initialize(dn,source = nil)
      @source = source
      dn = dn.dn if dn.respond_to?(:dn)
      if dn.respond_to?(:to_ary)
        dn = dn.map do |pair|
          if pair.kind_of?(Hash)
            LDAP::RDN(pair).to_str
          else
            pair
          end
        end * ','
      end
      if dn.include?(".") && !dn.include?("=")
        dn = dn.split(".").map {|dc| "DC=#{LDAP.escape(dc)}"} * ","
      end
      super(dn)
    end

    def to_dn
      self
    end

    # If a source object was given, it is used to search for the DN.
    # Otherwise, an exception is raised.
    def find(source = @source)
      scope = 0
      filter = "(objectClass=*)"
      if source.respond_to?(:search2_ext)
        source.search2(
          self.to_s,
          scope,
          filter
        )
      elsif source.respond_to?(:search)
        Array(source.search(
          :base => self.to_s,
          :scope => scope,
          :filter => filter
        ))
      else
        raise RuntimeError, "missing or invalid source for LDAP search", caller
      end.first
    end

    # Convert the DN to an array of RDNs.
    #
    #   LDAP::DN("cn=Thomas\\, David,dc=pragprog,dc=com").rdns
    #   # => [{:cn=>"Thomas, David"},{:dc=>"pragprog"},{:dc=>"com"}]
    def rdns
      rdn_strings.map {|rdn| RDN.new(rdn)}
    # rescue
      # raise RuntimeError, "error parsing DN", caller
    end

    def rdn_strings
      LDAP.split(self, ?,)
    end

    undef_method(:to_a)
    # ensure Array() doesn't call to_a by trapping it here
    def method_missing(method,*args,&block)
      if method.to_sym == :to_a
        rdns(*args,&block)
      else
        super(method,*args,&block)
      end
    end

    def parent
      LDAP::DN(rdns[1..-1], source)
    end

    def rdn
      rdns.first
    end

    def normalize
      LDAP::DN(rdns, source)
    end

    def normalize!
      replace(normalize)
    end

    # TODO: investigate compliance with
    # RFC4517 - Lightweight Directory Access Protocol (LDAP): Syntaxes and Matching Rules
    def ==(other)
      if other.respond_to?(:dn)
        other = LDAP::DN(other)
      end
      normalize = lambda do |hash|
        hash.inject({}) do |m,(k,v)|
          m[LDAP.escape(k).upcase] = v
          m
        end
      end
      if other.kind_of?(LDAP::DN)
        # self.to_a.map(&normalize) == other.to_a.map(&normalize)
        self.rdns == other.rdns
      else
        super
      end
    # rescue
      # super
    end

    # Pass in one or more hashes to augment the DN.  Otherwise, this behaves
    # the same as String#[]

    def [](*args)
      if args.first.kind_of?(Hash) || args.first.kind_of?(LDAP::DN)
        send(:/,*args)
      else
        super
      end
    end

    # Prepend an RDN to the DN.
    #
    #   LDAP::DN(:dc => "com")/{:dc => "foobar"} #=> "DC=foobar,DC=com"
    def /(*args)
      LDAP::DN(args.reverse + to_a, source)
    end

    # With a Hash (and only with a Hash), prepends a RDN to the DN, modifying
    # the receiver in place.  Otherwise, behaves like String#<<.
    def <<(arg)
      if arg.kind_of?(Hash)
        replace(self/arg)
      else
        super
      end
    end

    # With a Hash, check for the presence of an RDN.  Otherwise, behaves like
    # String#include?
    def include?(arg)
      if arg.kind_of?(Hash)
        rdns.include?(arg)
      else
        super
      end
    end

  end

  def self.RDN(rdn)
    rdn = rdn.rdn if rdn.respond_to?(:rdn)
    if rdn.respond_to?(:to_rdn)
      rdn.to_rdn
    else
      RDN.new(rdn||{})
    end
  end

  class RDN < Hash

    def self.parse_string(string) #:nodoc:

      LDAP.split(string, ?+).inject({}) do |hash, pair|
        k,v = LDAP.split(pair, ?=).map {|x| LDAP.unescape(x)}
        hash[k.downcase.to_sym] = v
        hash
      end

    rescue
      raise RuntimeError, "error parsing RDN", caller
    end

    def initialize(rdn = {})
      rdn = rdn.rdn if rdn.respond_to?(:rdn)
      if rdn.kind_of?(String)
        rdn = RDN.parse_string(rdn)
      end
      if rdn.kind_of?(Hash)
        super()
        update(rdn)
      else
        raise TypeError, "default value #{rdn.inspect} not allowed", caller
      end
    end

    def /(*args)
      LDAP::DN([self]).send(:/,*args)
    end

    def to_rdn
      self
    end

    def to_str
      collect do |k,v|
        "#{LDAP.escape(k,true)}=#{LDAP.escape(v)}"
      end.sort.join("+")
    end

    alias to_s to_str

    def downcase!
      values.each {|v| v.downcase!}
      self
    end

    def upcase!
      values.each {|v| v.upcase!}
      self
    end

    def downcase() clone.downcase! end
    def   upcase() clone.  upcase! end

    unless defined? MANDATORY_ATTRIBUTE_TYPES
      MANDATORY_ATTRIBUTE_TYPES = %w(CN L ST O OU C STREET DC UID)
    end

    MANDATORY_ATTRIBUTE_TYPES.map {|a| a.downcase.to_sym }.each do |type|
      define_method(type) { self[type] }
    end

    def [](*args)
      if args.size == 1
        if args.first.respond_to?(:to_sym)
          return super(convert_key(args.first))
        elsif args.first.kind_of?(Hash)
          return self/args.first
        end
      end
      to_str[*args]
    end

    def hash
      to_str.downcase.hash
    end

    def eql?(other)
      if other.respond_to?(:to_str)
        to_str.casecmp(other.to_str).zero?
      elsif other.kind_of?(Hash)
        eql?(LDAP::RDN(other)) rescue false
      else
        super
      end
    end

    alias == eql?

    def clone
      inject(RDN.new) do |h,(k,v)|
        h[k] = v.dup; h
      end
    end

    # Net::LDAP compatibility
    def to_ber #:nodoc:
      to_str.to_ber
    end

    # Based on ActiveSupport's HashWithIndifferentAccess

    alias_method :regular_writer, :[]= unless method_defined?(:regular_writer)
    alias_method :regular_update, :update unless method_defined?(:regular_update)

    def []=(key, value)
      regular_writer(convert_key(key), convert_value(value))
    end

    def update(other_hash)
      other_hash.each_pair { |key, value| regular_writer(convert_key(key), convert_value(value)) }
      self
    end

    alias_method :merge!, :update

    def key?(key)
      super(convert_key(key))
    end

    alias_method :include?, :key?
    alias_method :has_key?, :key?
    alias_method :member?, :key?

    def fetch(key, *extras)
      super(convert_key(key), *extras)
    end

    def values_at(*indices)
      indices.collect {|key| self[convert_key(key)]}
    end

    def dup
      RDN.new(self)
    end

    def merge(hash)
      self.dup.update(hash)
    end

    def delete(key)
      super(convert_key(key))
    end

    private

    def convert_key(key)
      if key.respond_to?(:to_str)
        key.to_str
      elsif key.respond_to?(:to_sym)
        key.to_sym.to_s
      else
        raise TypeError, "keys in an LDAP::RDN must be symbols", caller(1)
      end.downcase.to_sym
    end

    def convert_value(value)
      value.to_s
    end

  end
end

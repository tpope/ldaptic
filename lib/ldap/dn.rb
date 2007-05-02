require 'ldap/escape'

module LDAP

  # Instantiate a new LDAP::DN object with the arguments given.  Unlike
  # LDAP::DN.new(dn), this method coerces the first argument to a string,
  # unless it is already a string or an array.
  def self.DN(dn, source = nil)
    dn = dn.dn if dn.respond_to?(:dn)
    return dn if dn.kind_of?(::LDAP::DN)
    unless dn.respond_to?(:to_ary)
      dn = dn.to_s
    end
    DN.new(dn,source)
  end

  class DN < ::String

    attr_accessor :source

    # Create a new LDAP::DN object. dn can either be a string, or an array of
    # pairs.
    #
    #   LDAP::DN([["cn","Thomas, David"],["dc","pragprog"],["dc","com"]])
    #   # => "cn=Thomas\\, David,dc=pragprog,dc=com"
    #
    # The optional second object specifies either an LDAP::Conn object or a
    # Ldaptor object to be used to find the DN with #find.
    def initialize(dn,source = nil)
      @source = source
      dn = dn.dn if dn.respond_to?(:dn)
      if dn.respond_to?(:to_ary)
        dn = dn.map do |pair|
          pair.respond_to?(:join) ? pair.join("=") : pair
        end.map do |set|
          LDAP.escape(set)
        end * ','
      end
      super(dn)
    end

    # If a source object was given, it is used to search for the DN.
    # Otherwise, an exception is raised.
    def find
      if @source.respond_to?(:search2)
        @source.search2(self,::LDAP::LDAP_SCOPE_BASE,"(objectClass=*)").first
      elsif defined?(Ldaptor) && @source.respond_to?(:search)
        @source.search(:base_dn => self, :scope => ::LDAP::LDAP_SCOPE_BASE, :filter => "(objectClass=*)").first or raise Ldaptor::RecordNotFound
      else
        raise RuntimeError, "missing or invalid source for LDAP search", caller
      end
    end

    # Convert the DN to an array of pairs.
    #
    #   LDAP::DN("cn=Thomas\\, David,dc=pragprog,dc=com").to_a
    #   # => [["cn","Thomas, David"],["dc","pragprog"],["dc","com"]]
    def to_a
      return [] if empty?
      array = [""]
      backslash = nil
      each_byte do |byte|
        case backslash
        when true
          char = byte.chr
          if (?0..?9).include?(byte) || ('a'..'f').include?(char.downcase)
            backslash = char
          else
            array.last << byte
            backslash = nil
          end
        when String
          array.last << (backslash << char).to_i(16)
          backslash = nil
        else
          case byte
          when ?,
            array << ""
          when ?\\
            backslash = true
          else
            array.last << byte
          end
        end
      end
      array.map! do |entry|
        entry.match(/(.*?)=(.*)/)[1,2]
      end
      array
    rescue
      raise RuntimeError, "error parsing DN", caller
    end

    def <=>(other)
      if other.respond_to?(:dn)
        other = LDAP::DN(other)
      end
      if other.kind_of?(LDAP::DN)
        self.to_a.map do |(k,v)|
          [k.downcase,v]
        end <=> other.to_a.map do |(k,v)|
          [k.downcase,v]
        end
      else
        super
      end
    rescue
      super
    end

    def ==(other)
      return super unless other.kind_of?(LDAN::DN)
      (self <=> other) == 0
    rescue
      super
    end

  end
end

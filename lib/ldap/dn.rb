require 'ldap/escape'

module LDAP

  # Instantiate a new LDAP::DN object with the arguments given.  Unlike
  # LDAP::DN.new(dn), this method coerces the first argument to a string,
  # unless it is already a string or an array.  If the first argument is nil,
  # nil is returned.
  def self.DN(dn, source = nil)
    return nil if dn.nil?
    dn = dn.dn if dn.respond_to?(:dn)
    return dn if dn.kind_of?(::LDAP::DN)
    unless dn.respond_to?(:to_ary)
      dn = dn.to_s
    end
    DN.new(dn,source)
  end

  # RFC4512 - Lightweight Directory Access Protocol (LDAP): Directory Information Models
  # RFC4514 - Lightweight Directory Access Protocol (LDAP): String Representation of Distinguished Names
  #
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
      # TODO: support multivalued RDNs, e.g. CN=Kurt Zeilenga+L=Redwood Shores
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

        dest = array.last.kind_of?(Array) ? array.last.last : array.last
        case backslash
        when true
          char = byte.chr
          if (?0..?9).include?(byte) || ('a'..'f').include?(char.downcase)
            backslash = char
          else
            dest << byte
            backslash = nil
          end
        when String
          dest << (backslash << char).to_i(16)
          backslash = nil
        else
          case byte
          when ?,
            array << ""
          when ?+
            if array.last.kind_of?(Array)
              array.last << ""
            else
              array[-1] = [array.last,""]
            end
          when ?\\
            backslash = true
          else
            dest << byte
          end
        end
      end
      array.map! do |entry|
        if entry.kind_of?(Array)
          entry.map {|x|x.match(/(.*?)=(.*)/)[1,2]}
        else
          entry.match(/(.*?)=(.*)/)[1,2]
        end
      end
      array
    # rescue
      # raise RuntimeError, "error parsing DN", caller
    end

    # TODO: investigate compliance with
    # RFC4517 - Lightweight Directory Access Protocol (LDAP): Syntaxes and Matching Rules
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

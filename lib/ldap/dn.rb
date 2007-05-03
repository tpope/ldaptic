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

    #   LDAP::DN[{:dc => 'com'},{:dc => 'amazon'}]
    #   => "dc=amazon,dc=com"
    def self.[](*args)
      LDAP::DN(args.reverse)
    end

    MANDATORY_ATTRIBUTE_TYPES = %w(CN L ST O OU C STREET DC UID)

    attr_accessor :source

    # Create a new LDAP::DN object. dn can either be a string, or an array of
    # pairs.
    #
    #   LDAP::DN([{:cn=>"Thomas, David"},{:dc=>"pragprog"},{:dc=>"com"}])
    #   # => "CN=Thomas\\, David,DC=pragprog,DC=com"
    #
    # The optional second object specifies either an LDAP::Conn object or a
    # Ldaptor object to be used to find the DN with #find.
    def initialize(dn,source = nil)
      @source = source
      dn = dn.dn if dn.respond_to?(:dn)
      if dn.respond_to?(:to_ary)
        dn = dn.map do |pair|
          if pair.respond_to?(:to_ary) || pair.kind_of?(Hash)
            pair = pair.to_a.flatten
            ary = []
            (pair.size/2).times do |i|
              ary << ([LDAP.escape(pair[i*2],true),LDAP.escape(pair[i*2+1])] * '=')
            end
            ary.join("+")
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

    # If a source object was given, it is used to search for the DN.
    # Otherwise, an exception is raised.
    def find(source = @source)
      scope = 0
      filter = "(objectClass=*)"
      if defined?(LDAP::Conn) && source.kind_of?(LDAP::Conn)
        source.search2(
          self.to_s,
          scope,
          filter
        )
      elsif defined?(Net::LDAP) && source.kind_of?(Net::LDAP)
        source.search(
          :base => self.to_s,
          :scope => scope,
          :filter => filter
        )
      elsif defined?(Ldaptor) && source.respond_to?(:search)
        source.search(
          :base_dn => self.to_s,
          :scope => scope,
          :filter => filter
        )
      else
        raise RuntimeError, "missing or invalid source for LDAP search", caller
      end.first
    end

    # Convert the DN to an array of RDNs.
    #
    #   LDAP::DN("cn=Thomas\\, David,dc=pragprog,dc=com").to_a
    #   # => [{"cn"=>"Thomas, David"},{"dc"=>"pragprog"},{"dc"=>"com"}]
    def to_a
      return [] if empty?
      array = [""]
      backslash = hex = nil

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
          backslash = nil
          case byte
          when ?,
            array << ""
            hex = false
          when ?+
            hex = false
            if array.last.kind_of?(Array)
              array.last << ""
            else
              array[-1] = [array.last,""]
            end
          when ?\\
            hex = false
            backslash = true
          when ?=
            hex = true unless dest.include?("=")
            dest << byte
          when ?#
            if hex == true
              hex = ""
            else
              hex = false
              dest << byte
            end
          else
            if hex.kind_of?(String)
              hex << byte
              if hex.size == 2
                dest << hex.to_i(16)
                hex = ""
              end
            else
              dest << byte
            end
          end

        end
      end

      array.map! do |entry|
        if entry.kind_of?(Array)
          Hash[*entry.map {|x|x.match(/(.*?)=(.*)/)[1,2]}.flatten]
        else
          Hash[*entry.match(/(.*?)=(.*)/)[1,2].flatten]
        end
      end

      array

    rescue
      raise RuntimeError, "error parsing DN", caller
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
        self.to_a.map(&normalize) == other.to_a.map(&normalize)
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

    # With a hash (and only with a Hash), prepends a RDN to the DN, modifying
    # the receiver in place.  Otherwise, behaves like String#<<.
    def <<(arg)
      if arg.kind_of?(Hash)
        replace(self/arg)
      else
        super
      end
    end


  end
end

module LDAP

  def DN(dn, source = nil)
    unless dn.respond_to?(:to_ary)
      dn = dn.to_s
    end
    DN.new(dn,source)
  end

  class DN < ::String

    attr_accessor :source

    def initialize(dn,source = nil)
      @source = source
      if dn.respond_to?(:to_ary)
        dn = dn.map do |pair|
          pair.respond_to?(:join) ? pair.join("=") : pair
        end.map do |set|
          LDAP.escape(set)
        end * ','
      end
      super(dn)
    end

    def find
      if @source.respond_to?(:search2)
        @source.search2(self,::LDAP::LDAP_SCOPE_BASE,"(objectClass=*)").first
      elsif defined?(Ldaptor) && @source.respond_to?(:search)
        @source.search(:base_dn => self, :scope => ::LDAP::LDAP_SCOPE_BASE, :filter => "(objectClass=*)").first or raise Ldaptor::RecordNotFound
      else
        raise RuntimeError, "missing or invalid source for LDAP search", caller
      end
    end

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
        entry.match(/(.*?)=(.*)/)[1.2]
      end
      array
    rescue
      raise RuntimeError, "error parsing DN", caller
    end

  end
end

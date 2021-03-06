module Ldaptic

  # Encode an object with LDAP semantics.  Generally this is just to_s, but
  # dates and booleans get special treatment.
  #
  # If a symbol is passed in, underscores are replaced by dashes, aiding in
  # bridging the gap between LDAP and Ruby conventions.
  def self.encode(value)
    if value.respond_to?(:utc)
      value.dup.utc.strftime("%Y%m%d%H%M%S") + ".%06dZ" % value.usec
    elsif [true, false].include?(value)
      value.to_s.upcase
    elsif value.respond_to?(:dn)
      value.dn.dup
    elsif value.kind_of?(Symbol)
      value.to_s.gsub('_', '-')
    else
      value.to_s.dup
    end
  end

  # Escape a string for use in an LDAP filter, or in a DN.  If the second
  # argument is +true+, asterisks are not escaped.
  #
  # If the first argument is not a string, it is handed off to LDAP::encode.
  def self.escape(string, allow_asterisks = false)
    string = Ldaptic.encode(string)
    enc = lambda { |l| "\\%02X" % l.ord }
    string.gsub!(/[()\\\0-\37"+,;<>]/, &enc)
    string.gsub!(/\A[# ]| \Z/, &enc)
    if allow_asterisks
      string.gsub!('**', '\\\\2A')
    else
      string.gsub!('*', '\\\\2A')
    end
    string
  end

  def self.unescape(string)
    dest = ""
    string = string.strip # Leading and trailing whitespace MUST be encoded
    if string[0,1] == "#"
      [string[1..-1]].pack("H*")
    else
      backslash = nil
      string.each_byte do |byte|
        case backslash
        when true
          char = byte.chr
          if ('0'..'9').include?(char) || ('a'..'f').include?(char.downcase)
            backslash = char
          else
            dest << byte
            backslash = nil
          end

        when String
          dest << (backslash << byte).to_i(16)
          backslash = nil

        else
          backslash = nil
          if byte == 92 # ?\\
            backslash = true
          else
            dest << byte
          end
        end
      end
      dest
    end
  end

  # Split on a given character where it is not escaped.  Either an integer or
  # string represenation of the character may be used.
  #
  #   Ldaptic.split("a*b", '*')    # => ["a","b"]
  #   Ldaptic.split("a\\*b", '*')  # => ["a\\*b"]
  #   Ldaptic.split("a\\\\*b", ?*) # => ["a\\\\","b"]
  def self.split(string, character)
    return [] if string.empty?
    array = [""]
    character = character.to_str.ord if character.respond_to?(:to_str)
    backslash = false

    string.each_byte do |byte|
      if backslash
        array.last << byte
        backslash = false
      elsif byte == 92 # ?\\
        array.last << byte
        backslash = true
      elsif byte == character
        array << ""
      else
        array.last << byte
      end
    end
    array
  end

end

class String
  unless method_defined?(:ord)
    def ord
      self[0].to_i
    end
  end
end

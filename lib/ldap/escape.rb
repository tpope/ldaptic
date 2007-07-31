module LDAP #:nodoc:
  # Escape a string for use in an LDAP filter, or in a DN.  If the second
  # argument is +true+, asterisks are not escaped.
  #
  # But wait, there's more.  If a time or boolean object is passed in, it is
  # encoded LDAP style.  If a symbol is passed in, underscores are replaced by
  # dashes, aiding in bridging the gap between LDAP and Ruby conventions.
  def self.escape(string, allow_asterisks = false)
    if string.respond_to?(:utc)
      string = string.utc.strftime("%Y%m%d%H%M%S.0Z")
    elsif [true,false].include?(string)
      string = string.to_s.upcase
    end
    if string.kind_of?(Symbol)
      string = string.to_s.gsub('_','-')
      string.upcase! if allow_asterisks
    end
    string = string.to_s.dup
    enc = lambda {|l| "\\%02X" % l[0] }
    string.gsub!(/[()\\\0-\37"+,;<>]/,&enc)
    string.gsub!(/\A[# ]| \Z/,&enc)
    if allow_asterisks
      string.gsub!('**','\\\\2A')
    else
      string.gsub!('*','\\\\2A')
    end
    string
  end

  def self.unescape(string)
    dest = ""
    string = string.strip # Leading and trailing whitespace MUST be encoded
    if string[0] == ?#
      [string[1..-1]].pack("H*")
    else
      backslash = nil
      string.each_byte do |byte|
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
          dest << (backslash << byte).to_i(16)
          backslash = nil

        else
          backslash = nil
          if byte == ?\\
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
  #   LDAP.split("a*b",'*')    # => ["a","b"]
  #   LDAP.split("a\\*b",'*')  # => ["a\\*b"]
  #   LDAP.split("a\\\\*b",?*) # => ["a\\\\","b"]
  def self.split(string, character)
    return [] if string.empty?
    array = [""]
    character = character.to_str[0] if character.respond_to?(:to_str)
    backslash = false

    string.each_byte do |byte|
      if backslash
        array.last << byte
        backslash = false
      elsif byte == ?\\
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

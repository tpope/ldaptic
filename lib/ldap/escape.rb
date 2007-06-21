module LDAP
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
    enc = lambda {|l| "\\%02x" % l[0] }
    string.gsub!(/[()\\\0-\37"+,;<>]/,&enc)
    string.gsub!(/\A[# ]| \Z/,&enc)
    if allow_asterisks
      string.gsub!('**','\\\\2a')
    else
      string.gsub!('*','\\\\2a')
    end
    string
  end
end

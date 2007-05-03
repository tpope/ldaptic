module LDAP
  # Escape a string for use in an LDAP filter, or in a DN.  If the second
  # argument is +false+, asterisks are not escaped.
  #
  # But wait, there's more.  If a time or boolean object is passed in, it is
  # encoded LDAP style.  If a symbol is passed in, underscores are replaced by
  # dashes, aiding in bridging the gap between LDAP and Ruby conventions.
  def self.escape(string, escape_asterisks = true)
    string = string.utc.strftime("%Y%m%d%H%M%S.0Z") if string.respond_to?(:utc)
    string = string.to_s.upcase if [true,false].include?(string)
    string = string.to_s.gsub('_','-') if string.kind_of?(Symbol)
    enc = lambda {|l| "\\" + l[0].to_s(16) }
    string.to_s.
      gsub(/[()#{escape_asterisks ? :* : nil}\\\0-\37"+,;<>]/,&enc).
      gsub(/\A[# ]| \Z/,&enc)
  end
end

module LDAP
  # Escape a string for use in an LDAP filter, or in a DN.  If the second
  # argument is +false+, asterisks are not escaped.
  def self.escape(string, escape_asterisks = true)
    string = string.utc.strftime("%Y%m%d%H%M%S.0Z") if string.respond_to?(:utc)
    enc = lambda {|l| "\\" + l[0].to_s(16) }
    string.to_s.gsub(/^[# ]| $/,&enc).
      gsub(/[()#{escape_asterisks ? :* : nil}\\\0-\37"+,;<>]/,&enc)
  end
end

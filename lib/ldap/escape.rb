module LDAP
  # Escape a string for use in an LDAP filter.  If the second argument is
  # +false+, asterisks are not escaped.
  #
  # This method is suitable for constructing search queries, and for
  # constructing DNs.
  def self.escape(string, escape_asterisks = true)
    string = string.utc.strftime("%Y%m%d%H%M%S.0Z") if string.respond_to?(:utc)
    string.to_s.gsub(/[()#{escape_asterisks ? :* : nil}\\\0-\37,]/) {|l| "\\" + l[0].to_s(16) }
  end
end

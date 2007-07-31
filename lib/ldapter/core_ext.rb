class String
  # Translates hyphens to underscores and uppercases the first letter as per
  # the argument.  Deprecated.
  def ldapitalize!(upper = false)
    self[0,1] = self[0,1].send(upper ? :upcase : :downcase)
    self.gsub!('-','_')
    self
  end

  # Equivalent to
  #   string.dup.ldapitalize!
  def ldapitalize(upper = false)
    dup.ldapitalize!(upper)
  end
end


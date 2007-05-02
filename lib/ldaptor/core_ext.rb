class String
  def ldapitalize!(upper = false)
    self[0,1] = self[0,1].send(upper ? :upcase : :downcase)
    self.gsub!('-','_')
    self
  end

  def ldapitalize(upper = false)
    dup.ldapitalize!(upper)
  end
end


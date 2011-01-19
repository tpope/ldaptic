require 'ldapter/filter'

module LDAP #:nodoc:
  # Deprecated in favor of Ldapter::Filter
  def self.Filter(*args)
    Ldapter::Filter(*args)
  end

  Filter = Ldapter::Filter
end

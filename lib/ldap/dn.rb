require 'ldapter/dn'

module LDAP #:nodoc:

  # Deprecated in favor of Ldapter.DN
  def self.DN(*args)
    Ldapter::DN(*args)
  end

  # Deprecated in favor of Ldapter.RDN
  def self.RDN(*args)
    Ldapter::RDN(*args)
  end

  DN = Ldapter::DN
  RDN = Ldapter::RDN
end

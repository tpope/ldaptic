require 'ldapter/escape'

module LDAP #:nodoc:

  # Deprecated in favor of Ldapter.encode
  def self.encode(*args) #:nodoc:
    Ldapter.encode(*args)
  end

  # Deprecated in favor of Ldapter.escape
  def self.escape(*args) #:nodoc:
    Ldapter.escape(*args)
  end

  # Deprecated in favor of Ldapter.unescape
  def self.unescape(*args) #:nodoc:
    Ldapter.unescape(*args)
  end

  # Deprecated in favor of Ldapter.split
  def self.split(*args) #:nodoc:
    Ldapter.split(*args)
  end

end

$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldap/escape'
require 'test/unit'

class LDAPEscapeTest < Test::Unit::TestCase

  def test_escape
    assert_equal "\\28Hello\\5c\\2aworld!\\29", LDAP.escape("(Hello\\*world!)")
    assert_equal "\\28Hello\\5c*world!\\29", LDAP.escape("(Hello\\*world!)",false)
    assert_equal "\\23Good-bye\\2c world\\20", LDAP.escape("#Good-bye, world ")
  end

end

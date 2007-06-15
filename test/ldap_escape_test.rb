$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldap/escape'
require 'test/unit'

class LDAPEscapeTest < Test::Unit::TestCase

  def test_escape
    assert_equal "\\28Hello\\5c\\2aworld!\\29", LDAP.escape("(Hello\\*world!)")
    assert_equal "\\23Good-bye\\2c world\\20", LDAP.escape("#Good-bye, world ")
    assert_equal "a*b\\2ac\\00", LDAP.escape("a*b**c\0",true)
    assert_equal "TRUE", LDAP.escape(true)
    assert_equal "20000101123456.0Z", LDAP.escape(Time.utc(2000,1,1,12,34,56))
    assert_equal "foo-bar", LDAP.escape(:foo_bar)
    assert_equal "FOO-BAR", LDAP.escape(:foo_bar,true)
  end

end

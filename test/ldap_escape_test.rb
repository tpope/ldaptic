$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldap/escape'
require 'test/unit'

class LDAPEscapeTest < Test::Unit::TestCase

  PAIRS = [
    ["\\28Hello\\5C\\2Aworld!\\29", "(Hello\\*world!)"],
    ["\\23Good-bye\\2C world\\20", "#Good-bye, world "]
  ]

  def test_encode
    assert_equal "FALSE", LDAP.encode(false)
    assert_equal "20000101123456.0Z", LDAP.encode(Time.utc(2000,1,1,12,34,56))
    assert_equal "foo-bar", LDAP.encode(:foo_bar)
  end

  def test_escape
    PAIRS.each do |escaped, unescaped|
      assert_equal escaped, LDAP.escape(unescaped)
    end
    assert_equal "a*b\\2Ac\\00", LDAP.escape("a*b**c\0",true)
    assert_equal "TRUE", LDAP.escape(true)
    assert_equal "foo-bar", LDAP.escape(:foo_bar)
    # assert_equal "FOO-BAR", LDAP.escape(:foo_bar,true)
  end

  def test_should_not_mutate
    x = ","
    assert_equal "\\2C", LDAP.escape(x).upcase
    assert_equal ",", x
  end

  def test_unescape
    PAIRS.each do |escaped, unescaped|
      assert_equal unescaped, LDAP.unescape(escaped)
    end
    assert_equal " whitespace!", LDAP.unescape("  \\20whitespace\\!  ")
    assert_equal "abcde", LDAP.unescape("#6162636465")
  end

  def test_split
    assert_equal ["a","b"],     LDAP.split("a*b",'*')
    assert_equal ["a\\*b"],     LDAP.split("a\\*b",'*')
    assert_equal ["a\\\\","b"], LDAP.split("a\\\\*b",?*)
  end

end

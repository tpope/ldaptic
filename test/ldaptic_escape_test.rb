$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldaptic/escape'
require 'test/unit'

class LdapticEscapeTest < Test::Unit::TestCase

  PAIRS = [
    ["\\28Hello\\5C\\2Aworld!\\29", "(Hello\\*world!)"],
    ["\\23Good-bye\\2C world\\20", "#Good-bye, world "]
  ]

  def test_encode
    assert_equal "FALSE", Ldaptic.encode(false)
    assert_equal "20000101123456.000000Z", Ldaptic.encode(Time.utc(2000,1,1,12,34,56))
    assert_equal "foo-bar", Ldaptic.encode(:foo_bar)
  end

  def test_escape
    PAIRS.each do |escaped, unescaped|
      assert_equal escaped, Ldaptic.escape(unescaped)
    end
    assert_equal "a*b\\2Ac\\00", Ldaptic.escape("a*b**c\0", true)
    assert_equal "TRUE", Ldaptic.escape(true)
    assert_equal "foo-bar", Ldaptic.escape(:foo_bar)
  end

  def test_should_not_mutate
    x = ","
    assert_equal "\\2C", Ldaptic.escape(x).upcase
    assert_equal ",", x
  end

  def test_unescape
    PAIRS.each do |escaped, unescaped|
      assert_equal unescaped, Ldaptic.unescape(escaped)
    end
    assert_equal " whitespace!", Ldaptic.unescape("  \\20whitespace\\!  ")
    assert_equal "abcde", Ldaptic.unescape("#6162636465")
  end

  def test_split
    assert_equal ["a","b"],     Ldaptic.split("a*b", '*')
    assert_equal ["a\\*b"],     Ldaptic.split("a\\*b", '*')
    assert_equal ["a\\\\","b"], Ldaptic.split("a\\\\*b", ?*)
  end

end

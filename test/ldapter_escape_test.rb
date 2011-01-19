$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldapter/escape'
require 'test/unit'

class LdapterEscapeTest < Test::Unit::TestCase

  PAIRS = [
    ["\\28Hello\\5C\\2Aworld!\\29", "(Hello\\*world!)"],
    ["\\23Good-bye\\2C world\\20", "#Good-bye, world "]
  ]

  def test_encode
    assert_equal "FALSE", Ldapter.encode(false)
    assert_equal "20000101123456.0Z", Ldapter.encode(Time.utc(2000,1,1,12,34,56))
    assert_equal "foo-bar", Ldapter.encode(:foo_bar)
  end

  def test_escape
    PAIRS.each do |escaped, unescaped|
      assert_equal escaped, Ldapter.escape(unescaped)
    end
    assert_equal "a*b\\2Ac\\00", Ldapter.escape("a*b**c\0",true)
    assert_equal "TRUE", Ldapter.escape(true)
    assert_equal "foo-bar", Ldapter.escape(:foo_bar)
    # assert_equal "FOO-BAR", Ldapter.escape(:foo_bar,true)
  end

  def test_should_not_mutate
    x = ","
    assert_equal "\\2C", Ldapter.escape(x).upcase
    assert_equal ",", x
  end

  def test_unescape
    PAIRS.each do |escaped, unescaped|
      assert_equal unescaped, Ldapter.unescape(escaped)
    end
    assert_equal " whitespace!", Ldapter.unescape("  \\20whitespace\\!  ")
    assert_equal "abcde", Ldapter.unescape("#6162636465")
  end

  def test_split
    assert_equal ["a","b"],     Ldapter.split("a*b",'*')
    assert_equal ["a\\*b"],     Ldapter.split("a\\*b",'*')
    assert_equal ["a\\\\","b"], Ldapter.split("a\\\\*b",?*)
  end

end

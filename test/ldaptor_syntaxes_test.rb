$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldaptor/syntaxes'
require 'test/unit'

class LdaptorSyntaxesTest < Test::Unit::TestCase

  def test_for
    assert_equal Ldaptor::Syntaxes::GeneralizedTime, Ldaptor::Syntaxes.for("Generalized Time")
  end

  def test_booleans
    assert_equal true,    Ldaptor::Syntaxes::Boolean.parse("TRUE")
    assert_equal false,   Ldaptor::Syntaxes::Boolean.parse("FALSE")
    assert_equal "TRUE",  Ldaptor::Syntaxes::Boolean.format(true)
    assert_equal "FALSE", Ldaptor::Syntaxes::Boolean.format(false)
    assert_raise(TypeError) { Ldaptor::Syntaxes::Boolean.format(Object.new) }
  end

  def test_integers
    assert_equal 1,      Ldaptor::Syntaxes::INTEGER.parse("1")
    assert_equal "1",    Ldaptor::Syntaxes::INTEGER.format(1)
  end

  def test_time
    assert_equal Time.utc(2000,1,1,12,34,56), Ldaptor::Syntaxes::GeneralizedTime.parse("20000101123456.0Z")
    assert_equal "20000101123456.000000Z", Ldaptor::Syntaxes::GeneralizedTime.format(Time.utc(2000,1,1,12,34,56))
  end
end

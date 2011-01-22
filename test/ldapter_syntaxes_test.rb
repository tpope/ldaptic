require File.join(File.dirname(File.expand_path(__FILE__)),'test_helper')
require 'ldapter/syntaxes'

class LdapterSyntaxesTest < Test::Unit::TestCase

  def test_for
    assert_equal Ldapter::Syntaxes::GeneralizedTime, Ldapter::Syntaxes.for("Generalized Time")
  end

  def test_booleans
    assert_equal true,    Ldapter::Syntaxes::Boolean.parse("TRUE")
    assert_equal false,   Ldapter::Syntaxes::Boolean.parse("FALSE")
    assert_equal "TRUE",  Ldapter::Syntaxes::Boolean.format(true)
    assert_equal "FALSE", Ldapter::Syntaxes::Boolean.format(false)
  end

  def test_integers
    assert_equal 1,      Ldapter::Syntaxes::INTEGER.parse("1")
    assert_equal "1",    Ldapter::Syntaxes::INTEGER.format(1)
  end

  def test_time
    assert_equal Time.utc(2000,1,1,12,34,56), Ldapter::Syntaxes::GeneralizedTime.parse("20000101123456.0Z")
    assert_equal Time.utc(2000,1,1,12,34,56), Ldapter::Syntaxes::GeneralizedTime.parse("20000101123456.0Z")
    assert_equal 1601, Ldapter::Syntaxes::GeneralizedTime.parse("16010101000001.0Z").year
    assert_equal "20000101123456.000000Z", Ldapter::Syntaxes::GeneralizedTime.format(Time.utc(2000,1,1,12,34,56))
  end

  def test_delivery_method
    assert_not_nil Ldapter::Syntaxes::DeliveryMethod.new.error('')
  end

end

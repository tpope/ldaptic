require File.join(File.dirname(File.expand_path(__FILE__)),'test_helper')
require 'ldapter/syntaxes'

class LdapterSyntaxesTest < Test::Unit::TestCase

  def test_for
    assert_equal Ldapter::Syntaxes::GeneralizedTime, Ldapter::Syntaxes.for("Generalized Time")
  end

  def test_bit_string
    assert_nil Ldapter::Syntaxes::BitString.new.error("'01'B")
    assert_not_nil Ldapter::Syntaxes::BitString.new.error("01'B")
  end

  def test_boolean
    assert_equal true,    Ldapter::Syntaxes::Boolean.parse("TRUE")
    assert_equal false,   Ldapter::Syntaxes::Boolean.parse("FALSE")
    assert_equal "TRUE",  Ldapter::Syntaxes::Boolean.format(true)
    assert_equal "FALSE", Ldapter::Syntaxes::Boolean.format(false)
  end

  def test_generalized_time
    assert_equal Time.utc(2000,1,1,12,34,56), Ldapter::Syntaxes::GeneralizedTime.parse("20000101123456.0Z")
    assert_equal Time.utc(2000,1,1,12,34,56), Ldapter::Syntaxes::GeneralizedTime.parse("20000101123456.0Z")
    assert_equal 1601, Ldapter::Syntaxes::GeneralizedTime.parse("16010101000001.0Z").year
    assert_equal "20000101123456.000000Z", Ldapter::Syntaxes::GeneralizedTime.format(Time.utc(2000,1,1,12,34,56))
  end

  def test_ia5_string
    assert_nil Ldapter::Syntaxes::IA5String.new.error('a')
  end

  def test_integer
    assert_equal 1,   Ldapter::Syntaxes::INTEGER.parse("1")
    assert_equal "1", Ldapter::Syntaxes::INTEGER.format(1)
  end

  def test_printable_string
    assert_nil Ldapter::Syntaxes::PrintableString.new.error("Az0'\"()+,-./:? =")
    assert_not_nil Ldapter::Syntaxes::PrintableString.new('$')
    assert_not_nil Ldapter::Syntaxes::PrintableString.new("\\")
    assert_not_nil Ldapter::Syntaxes::PrintableString.new("\t")
  end

  def test_country_string
    assert_nil Ldapter::Syntaxes::CountryString.new.error('ab')
    assert_not_nil Ldapter::Syntaxes::CountryString.new.error('a')
    assert_not_nil Ldapter::Syntaxes::CountryString.new.error('abc')
    assert_not_nil Ldapter::Syntaxes::CountryString.new.error('a_')
  end

  def test_delivery_method
    assert_not_nil Ldapter::Syntaxes::DeliveryMethod.new.error('')
  end

  def test_facsimile_telephone_number
    assert_nil Ldapter::Syntaxes::FacsimileTelephoneNumber.new.error("911")
    assert_nil Ldapter::Syntaxes::FacsimileTelephoneNumber.new.error("911$b4Length")
    assert_not_nil Ldapter::Syntaxes::FacsimileTelephoneNumber.new("\t")
  end

end

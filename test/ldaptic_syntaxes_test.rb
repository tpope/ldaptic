require File.join(File.dirname(File.expand_path(__FILE__)),'test_helper')
require 'ldaptic/syntaxes'

class LdapticSyntaxesTest < Test::Unit::TestCase

  def test_for
    assert_equal Ldaptic::Syntaxes::GeneralizedTime, Ldaptic::Syntaxes.for("Generalized Time")
  end

  def test_bit_string
    assert_nil Ldaptic::Syntaxes::BitString.new.error("'01'B")
    assert_not_nil Ldaptic::Syntaxes::BitString.new.error("01'B")
  end

  def test_boolean
    assert_equal true,    Ldaptic::Syntaxes::Boolean.parse("TRUE")
    assert_equal false,   Ldaptic::Syntaxes::Boolean.parse("FALSE")
    assert_equal "TRUE",  Ldaptic::Syntaxes::Boolean.format(true)
    assert_equal "FALSE", Ldaptic::Syntaxes::Boolean.format(false)
  end

  def test_postal_address
    assert_not_nil Ldaptic::Syntaxes::PostalAddress.new.error('\\a')
  end

  def test_generalized_time
    assert_equal Time.utc(2000,1,1,12,34,56), Ldaptic::Syntaxes::GeneralizedTime.parse("20000101123456.0Z")
    assert_equal Time.utc(2000,1,1,12,34,56), Ldaptic::Syntaxes::GeneralizedTime.parse("20000101123456.0Z")
    assert_equal 1601, Ldaptic::Syntaxes::GeneralizedTime.parse("16010101000001.0Z").year
    assert_equal "20000101123456.000000Z", Ldaptic::Syntaxes::GeneralizedTime.format(Time.utc(2000,1,1,12,34,56))
  end

  def test_ia5_string
    assert_nil Ldaptic::Syntaxes::IA5String.new.error('a')
  end

  def test_integer
    assert_equal 1,   Ldaptic::Syntaxes::INTEGER.parse("1")
    assert_equal "1", Ldaptic::Syntaxes::INTEGER.format(1)
  end

  def test_printable_string
    assert_nil Ldaptic::Syntaxes::PrintableString.new.error("Az0'\"()+,-./:? =")
    assert_not_nil Ldaptic::Syntaxes::PrintableString.new('$')
    assert_not_nil Ldaptic::Syntaxes::PrintableString.new("\\")
    assert_not_nil Ldaptic::Syntaxes::PrintableString.new("\t")
  end

  def test_country_string
    assert_nil Ldaptic::Syntaxes::CountryString.new.error('ab')
    assert_not_nil Ldaptic::Syntaxes::CountryString.new.error('a')
    assert_not_nil Ldaptic::Syntaxes::CountryString.new.error('abc')
    assert_not_nil Ldaptic::Syntaxes::CountryString.new.error('a_')
  end

  def test_delivery_method
    assert_not_nil Ldaptic::Syntaxes::DeliveryMethod.new.error('')
  end

  def test_facsimile_telephone_number
    assert_nil Ldaptic::Syntaxes::FacsimileTelephoneNumber.new.error("911")
    assert_nil Ldaptic::Syntaxes::FacsimileTelephoneNumber.new.error("911$b4Length")
    assert_not_nil Ldaptic::Syntaxes::FacsimileTelephoneNumber.new("\t")
  end

end

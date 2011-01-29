require File.join(File.dirname(File.expand_path(__FILE__)),'test_helper')
require 'ldaptic/matching_rules'

class LdapticMatchingRulesTest < Test::Unit::TestCase
  include Ldaptic::MatchingRules

  def test_for
    assert_equal GeneralizedTimeMatch, Ldaptic::MatchingRules.for("generalizedTimeMatch")
  end

  def test_case_exact_match
    assert  CaseExactMatch.new.match('  A bc', 'A  bc')
    assert !CaseExactMatch.new.match('  A bc', 'a  bC')
  end

  def test_case_ignore_match
    assert CaseIgnoreMatch.new.match('  A bc', 'a  bC')
  end

  def test_generalized_time_match
    assert_equal Time.utc(2000,1,1,12,34,56), GeneralizedTimeMatch.new.matchable("20000101123456.0Z")
  end

  def test_numeric_string
    assert  NumericStringMatch.new.match(' 123  4', '123 4')
    assert !NumericStringMatch.new.match('1234', '1235')
  end

  def test_distinguished_name_match
    assert  DistinguishedNameMatch.new.match('a=1+b=2', 'B=2+A=1')
    assert !DistinguishedNameMatch.new.match('a=1,b=2', 'b=2,a=1')
  end

  def test_telephone_number_match
    assert TelephoneNumberMatch.new.match("911", "9  1-1-")
  end

end

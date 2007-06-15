$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldap/filter'
require 'test/unit'

class LDAPFilterTest < Test::Unit::TestCase

  def assert_ldap_filter(string, filter)
    assert_equal string, LDAP::Filter(filter).process
  end

  def test_filter_from_hash
    assert_ldap_filter nil, {}
    assert_ldap_filter "(x=1)", :x => 1
    assert_ldap_filter "(x=*)", :x => true
    assert_ldap_filter "(!(x=1))", :x! => 1
    assert_ldap_filter "(!(x=*))", :x => false
    assert_ldap_filter "(|(x=1)(x=2))", :x => [1, 2]
    assert_ldap_filter "(&(x>=1)(x<=2))", :x => (1..2)
    assert_ldap_filter "(&(x=1)(y=2))", :x => 1, :y => 2
    assert_ldap_filter "(&(x>=1)(!(x>=2)))", :x => (1...2)
  end

  def test_filter_from_lambda
    assert_ldap_filter "(x=1)", lambda { |ldap| ldap.x == 1 }
    assert_ldap_filter "(&(x>=1)(cn=*))", lambda { (x >= 1) & cn }
  end

  def test_escape_asterisks
    assert_ldap_filter "(x=\\2a)", :x => "*"
    assert_ldap_filter "(x=*)", :x => "*", :* => true
  end

  def test_boolean_logic
    assert_ldap_filter "(&(a=1)(b=2))", LDAP::Filter(:a => 1) & {:b => 2}
    assert_ldap_filter "(|(a=1)(b=2))", LDAP::Filter(:a => 1) | "(b=2)"
    assert_ldap_filter "(!(a=1))",     ~LDAP::Filter(:a => 1)
  end

  def test_conversions
    assert_equal "(a=1)", {:a => 1}.to_ldap_filter.to_s
  end

  def test_errors
    assert_raise(TypeError) { LDAP::Filter(Object.new) }
  end

end

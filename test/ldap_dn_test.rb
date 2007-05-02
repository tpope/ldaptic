require File.dirname(__FILE__)+'/../lib/ldap/dn'
require 'test/unit'

class LDAPDNTest < Test::Unit::TestCase

  def test_to_a
    assert_equal [%w(dc pragprog),%w(dc com)], LDAP::DN("dc=pragprog,dc=com").to_a
    assert_equal [[["a",","],["b","+"]],["c","\\"]], LDAP::DN("a=\\,+b=\\+,c=\\\\").to_a
  end

  def test_constructor
    assert_equal "dc=foo,dc=bar", LDAP::DN([["dc","foo"],["dc","bar"]])
    assert_equal nil, LDAP::DN(nil)
  end

  def test_equality
    # FIXME: fails
    # assert_equal LDAP::DN("dc=foo"), LDAP::DN("DC=foo")
  end

end

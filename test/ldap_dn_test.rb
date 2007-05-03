$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldap/dn'
require 'test/unit'

class LDAPDNTest < Test::Unit::TestCase

  def test_constructor
    assert_equal "dc=foo,ba=\\23#\\20", LDAP::DN([["dc","foo"],["ba","## "]])
    assert_equal "dc=foo+ba=bar", LDAP::DN([[["dc","foo"],["ba","bar"]]])
    assert_equal nil, LDAP::DN(nil)
  end

  def test_to_a
    assert_equal [{"dc"=>"pragprog"},{"dc"=>"com"}], LDAP::DN("dc=pragprog,dc=com").to_a
    assert_equal [{"a"=>",","b"=>"+"},{"c"=>"\\"}], LDAP::DN("a=\\,+b=\\+,c=\\\\").to_a
    assert_equal [{"a"=>"bcdefg"}], LDAP::DN("a=#626364656667").to_a
  end

  def test_equality
    assert_equal LDAP::DN("dc=foo"), LDAP::DN("DC=foo")
  end

end

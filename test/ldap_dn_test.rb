$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldap/dn'
require 'test/unit'

class LDAPDNTest < Test::Unit::TestCase

  class FakeSearch
    def search(options)
      [options]
    end
  end

  class FakeSearch2
    def search2(*args)
      [args]
    end
    alias search2_ext search2
  end

  def test_constructor
    assert_equal "dc=foo,ba=\\23#\\20,zy=x", LDAP::DN([{"dc","foo"},{"ba","## "},{"zy","x"}])
    assert_equal %w(BA=bar DC=foo), LDAP::DN([{:dc=>"foo",:ba=>"bar"}]).split('+').sort
    assert_equal "DC=pragprog,DC=com", LDAP::DN("pragprog.com")
    assert_equal "DC=com", LDAP::DN(:dc=>"com")
    assert_equal nil, LDAP::DN(nil)
  end

  def test_to_a
    assert_equal [{"dc"=>"pragprog"},{"dc"=>"com"}], LDAP::DN("dc=pragprog,dc=com").to_a
    assert_equal [{"a"=>",","b"=>"+"},{"c"=>"\\"}], LDAP::DN("a=\\,+b=\\+,c=\\\\").to_a
    assert_equal [{"a"=>" #"}], LDAP::DN("a=\\20\\#").to_a
    assert_equal [{"a"=>"bcdefg#"}], LDAP::DN("a=#626364656667#").to_a
  end

  def test_parent
    assert_equal LDAP::DN("dc=com"), LDAP::DN("dc=pragprog,dc=com").parent
    assert_instance_of String, LDAP::DN("dc=pragprog,dc=com").rdn
  end

  def test_children
    assert_equal LDAP::DN("dc=pragprog,dc=com"), LDAP::DN("dc=com")/"dc=pragprog"
    assert_equal LDAP::DN("DC=pragprog,DC=com"), LDAP::DN([:dc=>"com"])/{:dc=>"pragprog"}
    assert_equal LDAP::DN("DC=pragprog,DC=com"), LDAP::DN([:dc=>"com"])[:dc=>"pragprog"]
    dn = LDAP::DN("DC=com")
    dn << {:dc=>"pragprog"}
    assert_equal LDAP::DN("DC=pragprog,DC=com"), dn
  end

  def test_equality
    assert_equal LDAP::DN("dc=foo"), LDAP::DN("DC=foo")
  end

  def test_still_acts_like_a_string
    assert_equal ?a, LDAP::DN("a=b")[0]
    assert_equal "a=bc", (LDAP::DN("a=b") << "c")
    assert_equal LDAP::DN("a=b"), "a=b"
  end

  def test_find
    dn = LDAP::DN("a=b",FakeSearch.new)
    assert_equal "a=b", dn.find[:base]
    dn = LDAP::DN(dn, FakeSearch2.new)
    assert_equal "a=b", dn.find.first
  end

end

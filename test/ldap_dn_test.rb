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
    assert_equal "dc=foo,ba=\\23#\\20,zy=x", LDAP::DN([{"dc"=>"foo"},{"ba"=>"## "},{"zy"=>"x"}]).downcase
    assert_equal %w(BA=bar DC=foo), LDAP::DN([{:dc=>"foo",:ba=>"bar"}]).split('+').sort
    assert_equal "DC=pragprog,DC=com", LDAP::DN("pragprog.com")
    assert_equal "DC=com", LDAP::DN(:dc=>"com")
    assert_equal nil, LDAP::DN(nil)
  end

  def test_rdns
    assert_equal [{:dc=>"pragprog"},{:dc=>"com"}], LDAP::DN("dc=pragprog,dc=com").rdns
    assert_equal [{:a=>",",:b=>"+"},{:c=>"\\"}], LDAP::DN("a=\\,+b=\\+,c=\\\\").rdns
    assert_equal [{:a=>" #"}], LDAP::DN("a=\\20\\#").rdns
    assert_equal [{:a=>"bcdefg"}], LDAP::DN("a=#626364656667").rdns
    assert  LDAP::DN("DC=foo").include?(:dc=>"Foo")
    assert !LDAP::DN("dc=foo").include?(:dc=>"Bar")
  end

  def test_parent
    assert_equal LDAP::DN("dc=com"), LDAP::DN("dc=pragprog,dc=com").parent
    assert_instance_of LDAP::RDN, LDAP::DN("dc=pragprog,dc=com").rdn
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
    assert_equal LDAP::RDN(:dc => "com"), LDAP::RDN('DC' => 'COM')
    assert LDAP::RDN(:dc => "com") != {Object.new => true}
    assert LDAP::RDN(:dc => "com") != 42
  end

  def test_still_acts_like_a_string
    dn = LDAP::DN("a=b")
    assert_equal ?a, dn[0]
    assert_equal dn, "a=b"
    assert_equal [dn], Array(dn)
    assert_raise(NoMethodError) { dn.unknown_method }
    assert dn.include?("=")
    assert_equal "a=bc", (LDAP::DN("a=b") << "c")
  end

  def test_should_search
    dn = LDAP::DN("a=b",FakeSearch.new)
    assert_equal "a=b", dn.find[:base]
    dn = LDAP::DN(dn, FakeSearch2.new)
    assert_equal "a=b", dn.find.first
  end

  def test_rdn
    rdn = LDAP::RDN.new("street=Main+cn=Doe, John")
    assert_kind_of LDAP::RDN, rdn.dup
    assert_kind_of LDAP::RDN, rdn.clone
    assert_equal "CN=Doe\\2c John+STREET=Main", rdn.to_str
    assert_equal "MAIN", rdn.upcase.street
    assert_equal "Main", rdn["Street"]
    rdn.downcase!
    assert_equal "main", rdn.street
    assert_equal "main", rdn.delete(:Street)
    assert_equal "CN=doe\\2c john+STREET=Main", rdn.merge(:street=>"Main").to_str
  end

  def test_rdn_lookup
    rdn = LDAP::RDN.new(:street=>"Main", :cn=>"Doe, John")
    assert_equal "OU=Corporate,CN=Doe\\2c John+STREET=Main", rdn[:ou=>"Corporate"].to_str
    assert rdn.has_key?(:street)
    assert rdn.include?('Street')
    assert_equal "CN=", rdn[(0..2)]
    assert_equal ["Main","Doe, John"], rdn.values_at(:street, 'CN')
    assert_raise(IndexError) { rdn.fetch(:uid) }
    assert_nothing_raised    { rdn.fetch("STREET") }
  end

  def test_rdn_as_key
    hash = {}
    hash[LDAP::RDN(:cn => "Doe, John")] = true
    assert hash[LDAP::RDN("Cn=doe\\, john")]
  end

  def test_rdn_should_raise_type_error
    assert_raise(TypeError) { LDAP::RDN(Object.new) }
    assert_raise(TypeError) { LDAP::RDN(Object.new => "whee") }
  end

end

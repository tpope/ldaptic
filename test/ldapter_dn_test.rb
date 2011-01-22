$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldapter/dn'
require 'test/unit'

class LdapterDNTest < Test::Unit::TestCase

  class FakeSearch
    def search(options)
      [options] end
  end

  class FakeSearch2
    def search2(*args)
      [args]
    end
    alias search2_ext search2
  end

  def test_constructor
    assert_equal "dc=foo,ba=\\23#\\20,zy=x", Ldapter::DN([{"dc"=>"foo"},{"ba"=>"## "},{"zy"=>"x"}]).downcase
    assert_equal %w(BA=bar DC=foo), Ldapter::DN([{:dc=>"foo",:ba=>"bar"}]).split('+').sort
    assert_equal "DC=pragprog,DC=com", Ldapter::DN("pragprog.com")
    assert_equal "DC=com", Ldapter::DN(:dc=>"com")
    assert_equal nil, Ldapter::DN(nil)
  end

  def test_rdns
    assert_equal [{:dc=>"pragprog"},{:dc=>"com"}], Ldapter::DN("dc=pragprog,dc=com").rdns
    assert_equal [{:a=>",",:b=>"+"},{:c=>"\\"}], Ldapter::DN("a=\\,+b=\\+,c=\\\\").rdns
    assert_equal [{:a=>" #"}], Ldapter::DN("a=\\20\\#").rdns
    assert_equal [{:a=>"bcdefg"}], Ldapter::DN("a=#626364656667").rdns
    assert  Ldapter::DN("DC=foo").include?(:dc=>"Foo")
    assert !Ldapter::DN("dc=foo").include?(:dc=>"Bar")
  end

  def test_parent
    assert_equal Ldapter::DN("dc=com"), Ldapter::DN("dc=pragprog,dc=com").parent
    assert_instance_of Ldapter::RDN, Ldapter::DN("dc=pragprog,dc=com").rdn
  end

  def test_children
    assert_equal Ldapter::DN("dc=pragprog,dc=com"), Ldapter::DN("dc=com")/"dc=pragprog"
    assert_equal Ldapter::DN("DC=pragprog,DC=com"), Ldapter::DN([:dc=>"com"])/{:dc=>"pragprog"}
    assert_equal Ldapter::DN("DC=pragprog,DC=com"), Ldapter::DN([:dc=>"com"])[:dc=>"pragprog"]
    dn = Ldapter::DN("DC=com")
    dn << {:dc=>"pragprog"}
    assert_equal Ldapter::DN("DC=pragprog,DC=com"), dn
  end

  def test_equality
    assert_equal Ldapter::DN("dc=foo"), Ldapter::DN("DC=foo")
    assert_equal Ldapter::RDN(:dc => "com"), Ldapter::RDN('DC' => 'COM')
    assert Ldapter::RDN(:dc => "com") != {Object.new => true}
    assert Ldapter::RDN(:dc => "com") != 42
  end

  def test_still_acts_like_a_string
    dn = Ldapter::DN("a=b")
    assert_equal ?a, dn[0]
    assert_equal dn, "a=b"
    assert_kind_of String, Array(dn).first
    assert_raise(NoMethodError) { dn.unknown_method }
    assert dn.include?("=")
    assert_equal "a=bc", (Ldapter::DN("a=b") << "c")
  end

  def test_should_search
    dn = Ldapter::DN("a=b", FakeSearch.new)
    assert_equal "a=b", dn.find[:base]
    dn = Ldapter::DN(dn, FakeSearch2.new)
    assert_equal "a=b", dn.find.first
  end

  def test_rdn
    rdn = Ldapter::RDN.new("street=Main+cn=Doe, John")
    assert_kind_of Ldapter::RDN, rdn.dup
    assert_kind_of Ldapter::RDN, rdn.clone
    assert_equal "CN=Doe\\2C John+STREET=Main", rdn.to_str
    assert_equal "MAIN", rdn.upcase.street
    assert_equal "Main", rdn["Street"]
    rdn.downcase!
    assert_equal "main", rdn.street
    assert_equal "main", rdn.delete(:Street)
    assert_equal "CN=doe\\2C john+STREET=Main", rdn.merge(:street=>"Main").to_str
  end

  def test_rdn_lookup
    rdn = Ldapter::RDN.new(:street=>"Main", :cn=>"Doe, John")
    assert_equal "OU=Corporate,CN=Doe\\2C John+STREET=Main", rdn[:ou=>"Corporate"].to_str
    assert rdn.has_key?(:street)
    assert rdn.include?('Street')
    assert_equal "CN=", rdn[(0..2)]
    assert_equal ["Main", "Doe, John"], rdn.values_at(:street, 'CN')
    error_class = {}.fetch(1) rescue $!.class
    assert_raise(error_class) { rdn.fetch(:uid) }
    assert_nothing_raised     { rdn.fetch("STREET") }
  end

  def test_rdn_as_key
    hash = {}
    hash[Ldapter::RDN(:cn => "Doe, John")] = true
    assert hash[Ldapter::RDN("Cn=doe\\, john")]
  end

  def test_rdn_should_raise_type_error
    assert_raise(TypeError) { Ldapter::RDN(Object.new) }
    assert_raise(TypeError) { Ldapter::RDN(Object.new => "whee") }
  end

end

require File.join(File.dirname(File.expand_path(__FILE__)),'test_helper')
require 'ldaptic'
require File.join(File.dirname(File.expand_path(__FILE__)),'/mock_adapter')

class LdapticHierarchyTest < Test::Unit::TestCase
  class Mock < Ldaptic::Class(:adapter => :mock)
  end

  def test_inheritance
    assert defined? Mock::Top
    assert_raise(NoMethodError) { Mock.new }
    assert_equal Mock::Top, Mock::Person.superclass
    assert Mock::Person.method_defined?(:sn)
    assert Mock::Person.method_defined?(:surname)
    assert !Mock::Top.method_defined?(:sn)
    assert_equal [], Mock::Top.aux
    assert_equal %w(simpleSecurityObject), Mock::Person.aux
  end

  def test_new
    person = Mock::Person.new(:dn => "CN=Matz,DC=org")
    assert !person.persisted?
    assert_equal "Matz", person.cn
    person.sn = "Matsumoto"
    assert_equal "Matsumoto", person.sn
    assert_equal %w"Matsumoto", person[:sn]
    assert_equal %w"Matsumoto", person['sn']
    assert_equal Ldaptic::DN("cn=Matz,dc=org"), person.dn
    assert_equal "CN=Matz", person.rdn
    inspect = person.inspect
    assert_raise(TypeError) { person.distinguishedName = "Why" }
    assert_raise(NoMethodError) { person.fakeAttribute = 42 }
    assert inspect.include?("Mock::Person CN=Matz,DC=org")
    assert_match(/sn: .*Matsumoto/, inspect)
  end

  def test_new_with_aux
    person = Mock::Person.new(:dn => "CN=Matz,DC=org")
    assert_raise(NoMethodError) { person.userPassword }
    person.instance_variable_get(:@attributes)["objectClass"] |= ["simpleSecurityObject"]
    assert_equal [Mock::Person, Mock::Top, Mock::SimpleSecurityObject], person.ldap_ancestors
    assert_nothing_raised { person.userPassword = ["ruby"] }
    assert_equal %w(ruby), person.userPassword
  end

  def test_attributes
    assert_equal %w(age sn), Mock::Person.may(false).sort
    assert_equal %w(age description distinguishedName sn), Mock::Person.may.sort
    assert_equal %w(cn), Mock::Person.must(false).sort
    assert_equal %w(cn objectClass), Mock::Person.must.sort
    assert_equal %w(cn description distinguishedName objectClass), Mock::Top.attributes
  end

  def test_search
    assert_kind_of Hash,   Mock.search(:limit => true, :instantiate => false)
    assert_kind_of Array,  Mock.search(:limit => false)
    assert_kind_of String, Mock.search(:attributes => :filter, :limit => false).first
    assert_kind_of Array,  Mock.search(:attributes => :filter, :instantiate => false).first
  end

  def test_find
    assert defined? Mock::SearchResult
    result = Mock.find("CN=Matz,DC=org")
    assert result.persisted?
    assert_equal "CN=Matz,DC=org", result.dn
    assert_equal 0, result.scope
    result = Mock.find(["CN=Matz,DC=org", "CN=Why,DC=org"])
    assert_equal 2, result.size
  end

  def test_children
    matz = Mock.find("CN=Matz,DC=org")
    assert_equal 0, (matz/{:child=>:data}).scope
    assert_equal 0, matz[:child=>:data].scope
    matz[:child=>:data].scope = 1
    # Verify cache is working
    assert_equal 1, matz[:child=>:data].scope
    assert_equal "DC=org", matz.parent.dn
    Mock.filter(true) do
      Mock[:cn=>"Matz"].scope = 1
      assert_equal 1, Mock[:cn=>"Matz"].scope
    end
    assert_equal 0, Mock[:cn=>"Matz"].scope
  end

  def test_schema
    assert Mock.schema([:objectClass, :scope]).scope
  end

end


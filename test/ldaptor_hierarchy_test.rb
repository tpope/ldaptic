$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldaptor'
require File.join(File.dirname(__FILE__),"/mock_adapter")
require 'test/unit'

class LdaptorHierarchyTest < Test::Unit::TestCase
  class Mock < Ldaptor::Namespace(:adapter => :mock)
  end

  def test_inheritance
    assert defined? Mock::Top
    assert_equal Mock::Top, Mock::Person.superclass
    assert Mock::Person.method_defined?(:sn)
    assert !Mock::Top.method_defined?(:sn)
    assert_equal [], Mock::Top.aux
    assert_equal %w(simpleSecurityObject), Mock::Person.aux
  end

  def test_new
    person = Mock::Person.new(:dn => "CN=Matz,DC=org")
    assert_equal "Matz", person.cn
    person.sn = "Matsumoto"
    assert_equal "Matsumoto", person.sn
    assert_equal "Matsumoto", person[:sn]
    assert_equal "Matsumoto", person['sn']
    assert_equal LDAP::DN("cn=Matz,dc=org"), person.dn
    assert_equal "CN=Matz", person.rdn
    inspect = person.inspect
    assert_raise(Ldaptor::Error) { person.distinguishedName = "Why" }
    assert_raise(NoMethodError) { person.fakeAttribute = 42 }
    assert inspect.include?("Mock::Person CN=Matz,DC=org")
    assert_match(/cn: .*Matsumoto/, inspect)
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
    assert_equal %w(sn), Mock::Person.may(false).sort
    assert_equal %w(description distinguishedName sn), Mock::Person.may.sort
    assert_equal %w(cn), Mock::Person.must(false).sort
    assert_equal %w(cn objectClass), Mock::Person.must.sort
    assert_equal %w(cn description distinguishedName objectClass), Mock::Top.attributes
  end

  def test_find
    assert defined? Mock::SearchResult
    result = Mock.find("CN=Matz,DC=org")
    assert_equal "CN=Matz,DC=org", result.dn
    assert_equal 0, result.scope
    result = Mock.find(["CN=Matz,DC=org","CN=Why,DC=org"])
    assert_equal 2, result.size
  end

  def test_children
    matz = Mock.find("CN=Matz,DC=org")
    assert_equal 0, matz.child("data").scope
    assert_equal 1, matz.child(:*).first.scope
    assert_equal '(child=*)', matz.child(:*).first.filter
    assert_equal 0, (matz/{:child=>:data}).scope
    assert_equal 0, matz[:child=>:data].scope
    assert_equal "DC=org", matz.parent.dn
    assert_equal "(objectClass=*)", matz.children.first.filter
  end
end


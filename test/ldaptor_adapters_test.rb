$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldaptor/adapters'
require 'ldaptor/adapters/net_ldap_adapter'
require 'ldaptor/adapters/ldap_conn_adapter'
require 'test/unit'

class LdaptorHierarchyTest < Test::Unit::TestCase
  def setup
    @ldap_conn = Ldaptor::Adapters::LDAPConnAdapter.allocate
    @net_ldap  = Ldaptor::Adapters::NetLDAPAdapter.allocate
  end

  def test_search_parameters
    assert_equal(
      ["DC=org",0,"(objectClass=*)",nil,false,1,10_000,"", nil],
      @ldap_conn.send(:search_parameters,
        :base => "DC=org",
        :scope => 0,
        :filter => "(objectClass=*)",
        :attributes_only => false,
        :timeout => 1.01
      )
    )
  end

  def test_recapitalize
    assert_equal "objectClass", @net_ldap.send(:recapitalize, "objectclass")
  end

  def test_incorrect_adapter
    assert_raise(ArgumentError) { Ldaptor::Adapters.for(:adapter => "fake") }
    assert_raise(TypeError)     { Ldaptor::Adapters.for(Object.new) }
    assert_not_nil Ldaptor::Adapters.for(@ldap_conn)
  end

end

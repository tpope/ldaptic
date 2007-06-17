$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldaptor/adapters'
require 'ldaptor/adapters/net_ldap_adapter'
require 'ldaptor/adapters/ldap_adapter'
require 'test/unit'

class LdaptorHierarchyTest < Test::Unit::TestCase
  def setup
    @ldap     = Ldaptor::Adapters::LDAPAdapter.allocate
    @net_ldap = Ldaptor::Adapters::NetLDAPAdapter.allocate
  end

  def test_search_parameters
    assert_equal(
      ["DC=org",0,"(objectClass=*)",nil,false,1,10_000,"", nil],
      @ldap.send(:search_parameters,
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

end

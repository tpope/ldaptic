$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldaptor/adapters'
require 'test/unit'

class LdaptorHierarchyTest < Test::Unit::TestCase
  def setup
    @ldap     = Ldaptor::Adapters::LDAPAdapter.new(nil)
    @net_ldap = Ldaptor::Adapters::NetLDAPAdapter.new(nil)
  end

  def test_search_options
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

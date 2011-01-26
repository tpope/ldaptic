require File.join(File.dirname(File.expand_path(__FILE__)),'test_helper')
require 'ldaptic/adapters'
require 'ldaptic/adapters/net_ldap_adapter'
require 'ldaptic/adapters/ldap_conn_adapter'

class LdapticAdaptersTest < Test::Unit::TestCase
  def setup
    @ldap_conn = Ldaptic::Adapters::LDAPConnAdapter.allocate
    @net_ldap  = Ldaptic::Adapters::NetLDAPAdapter.allocate
  end

  def test_should_parameterize_search_options
    assert_equal(
      ["DC=org", 0, "(objectClass=*)", nil, false, 1, 10_000, "", nil],
      @ldap_conn.instance_eval { search_parameters(
        :base => "DC=org",
        :scope => 0,
        :filter => "(objectClass=*)",
        :attributes_only => false,
        :timeout => 1.01
      )}
    )
  end

  def test_should_recapitalize
    assert_equal "objectClass", @net_ldap.instance_eval { recapitalize("objectclass") }
  end

  def test_should_reject_invalid_adapter_options
    assert_raise(ArgumentError) { Ldaptic::Adapters.for(:adapter => "fake") }
    assert_raise(TypeError)     { Ldaptic::Adapters.for(Object.new) }
    assert_not_nil Ldaptic::Adapters.for(@ldap_conn)
  end

end

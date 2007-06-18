require 'ldaptor/adapters/ldap_conn_adapter'

module Ldaptor
  module Adapters
    class LDAPSSLConnAdapter < LDAPConnAdapter
      register_as(:ldap_sslconn)
      private
      def connection_class
        LDAP::SSLConn
      end
    end
  end
end

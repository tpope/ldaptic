require 'ldapter/adapters/ldap_conn_adapter'

module Ldapter
  module Adapters
    # This adapter is entirely untested.
    class LDAPSSLConnAdapter < LDAPConnAdapter
      register_as(:ldap_sslconn)
      private
      def connection_class
        LDAP::SSLConn
      end
    end
  end
end

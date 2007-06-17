module Ldaptor
  module Adapters

    def self.for(options)
      if defined?(::LDAP::Conn) && options.kind_of?(::LDAP::Conn)
        require 'ldaptor/adapters/ldap_adapter'
        ::Ldaptor::Adapters::LDAPAdapter.new(options)
      elsif defined?(::Net::LDAP) && options.kind_of?(::Net::LDAP)
        require 'ldaptor/adapters/net_ldap_adapter'
        ::Ldaptor::Adapters::NetLDAPAdapter.new(options)
      else
        require 'ldaptor/adapters/abstract_adapter'
        if options.kind_of?(::Ldaptor::Adapters::AbstractAdapter)
          options
        else
          raise TypeError, "#{options.class} is not a valid connection type", caller[1..-1]
        end
      end
    end

  end
end

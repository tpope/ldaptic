require 'ldaptor/adapters/abstract_adapter'

module Ldaptor
  module Adapters
    class LDAPAdapter < AbstractAdapter
      register_as(:ldap)

      def initialize(options)
        require 'ldap'
        if defined?(::LDAP::Conn) && options.kind_of?(::LDAP::Conn)
          options = {:adapter => :ldap, :connection => options}
        end
        unless options[:connection]
          options[:connection] = ::LDAP::Conn.new(options[:host], options[:port])
          options[:connection].bind(options[:username], options[:password])
        end
        @options = options
        @connection = options[:connection]
      end

      def add(dn, attributes)
        @connection.add(dn, attributes)
      end

      def modify(dn, attributes)
        @connection.modify(dn, attributes)
      end

      def delete(dn)
        @connection.delete(dn)
      end

      def rename(dn, new_rdn, delete_old)
        @connection.modrdn(dn,new_rdn, delete_old)
      end

      def search(options = {}, &block)
        cookie = ""
        options = search_options(options)
        parameters = search_parameters(options)
        while cookie
          ctrl = paged_results_control(cookie)
          @connection.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS,[ctrl])
          result = @connection.search2(*parameters, &block)
          ctrl = @connection.controls.detect {|c| c.oid == ctrl.oid}
          cookie = ctrl && ctrl.decode.last
          cookie = nil if cookie.to_s.empty?
        end
      ensure
        @connection.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS,[]) rescue nil
      end

      private
      def paged_results_control(cookie = "", size = 126) # Namespace
        require 'ldap/control'
        # values above 126 cause problems for slapd, as determined by net/ldap
        ::LDAP::Control.new(
          # ::LDAP::LDAP_CONTROL_PAGEDRESULTS,
          "1.2.840.113556.1.4.319",
          ::LDAP::Control.encode(size,cookie),
          false
        )
      end

      def search_parameters(options = {}) # Namespace
        case options[:sort]
        when Proc, Method then s_attr, s_proc = nil, options[:sort]
        else s_attr, s_proc = options[:sort], nil
        end
        [
          options[:base],
          options[:scope],
          options[:filter],
          options[:attributes] && Array(options[:attributes]),
          options[:attributes_only],
          options[:timeout].to_i,
          ((options[:timeout].to_f % 1) * 1e6).round,
          s_attr.to_s,
          s_proc
        ]
      end

    end
  end
end

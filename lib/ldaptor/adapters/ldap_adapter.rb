require 'ldaptor/adapters/abstract_adapter'

module Ldaptor
  module Adapters
    class LDAPAdapter < AbstractAdapter
      register_as(:ldap)

      def initialize(options)
        require 'ldap'
        if defined?(::LDAP::Conn) && options.kind_of?(::LDAP::Conn)
          options = {:adapter => :ldap, :connection => options}
        else
          options = options.dup
        end
        unless options[:connection]
          options[:version] ||= 3
          options[:connection] = ::LDAP::Conn.new(options[:host], options[:port])
          options[:connection].set_option(::LDAP::LDAP_OPT_PROTOCOL_VERSION, options[:version])
          pw = options[:password]
          pw = pw.call if pw.respond_to?(:call)
          options[:connection].bind(options[:username], pw)
        end
        @options = options
        @connection = options[:connection]
      end

      def add(dn, attributes)
        with_writer do |conn|
          conn.add(dn, attributes)
        end
      end

      def modify(dn, attributes)
        with_writer do |conn|
          conn.modify(dn, attributes)
        end
      end

      def delete(dn)
        with_writer do |conn|
          conn.delete(dn)
        end
      end

      def rename(dn, new_rdn, delete_old)
        with_writer do |conn|
          conn.modrdn(dn,new_rdn, delete_old)
        end
      end

      def search(options = {}, &block)
        options = search_options(options)
        parameters = search_parameters(options)
        with_reader do |conn|
          begin
            cookie = ""
            while cookie
              ctrl = paged_results_control(cookie)
              conn.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS,[ctrl])
              result = conn.search2(*parameters, &block)
              ctrl   = conn.controls.detect {|c| c.oid == ctrl.oid}
              cookie = ctrl && ctrl.decode.last
              cookie = nil if cookie.to_s.empty?
            end
          ensure
            conn.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS,[]) rescue nil
          end
        end
      end

      private

      def with_reader
        yield @connection
      end

      def with_writer
        yield @connection
      end

      def paged_results_control(cookie = "", size = 126)
        require 'ldap/control'
        # values above 126 cause problems for slapd, as determined by net/ldap
        ::LDAP::Control.new(
          # ::LDAP::LDAP_CONTROL_PAGEDRESULTS,
          "1.2.840.113556.1.4.319",
          ::LDAP::Control.encode(size,cookie),
          false
        )
      end

      def search_parameters(options = {})
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

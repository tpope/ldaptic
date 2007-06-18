require 'ldaptor/adapters/abstract_adapter'

module Ldaptor
  module Adapters
    class LDAPConnAdapter < AbstractAdapter
      register_as(:ldap_conn)

      def initialize(options)
        require 'ldap'
        if defined?(::LDAP::Conn) && options.kind_of?(::LDAP::Conn)
          @options = {:adapter => :ldap_conn, :connection => options}
        else
          @options = options.dup
        end
        @options[:version] ||= 3
        unless @options[:connection]
          @options[:connection] = new_connection
          bind_connection(@options[:connection], @options[:username], @options[:password])
        end
        @connection = @options[:connection]
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
        parameters = search_parameters(options)
        with_reader do |conn|
          raise "AW FUCK" if conn.nil?
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

      def authenticate(dn, password)
        conn = new_connection
        bind_connection(conn, dn, password)
        true
      rescue LDAP::ResultError
        false
      ensure
        conn.unbind rescue nil
      end

      private

      def connection_class
        ::LDAP::Conn
      end

      def new_connection(default_port = nil)
        conn = connection_class.new(
          @options[:host]||"localhost",
          *[@options[:port] || default_port].compact
        )
        conn.set_option(::LDAP::LDAP_OPT_PROTOCOL_VERSION, @options[:version])
        conn
      end

      def bind_connection(conn, dn, password)
        password = password.call if password.respond_to?(:call)
        conn.bind(dn, password, *[@options[:method]].compact)
      end

      def with_reader
        err = 0
        begin
          yield @connection
        rescue ::LDAP::ResultError
          err = -1
        end
        @connection.err.to_i.zero? ? err : conn.err.to_i
      end

      alias with_writer with_reader

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

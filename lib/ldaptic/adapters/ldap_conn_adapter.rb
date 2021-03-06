require 'ldaptic/adapters/abstract_adapter'

module Ldaptic
  module Adapters
    class LDAPConnAdapter < AbstractAdapter
      register_as(:ldap_conn)

      def initialize(options)
        require 'ldap'
        if defined?(::LDAP::Conn) && options.kind_of?(::LDAP::Conn)
          options = {:adapter => :ldap_conn, :connection => options}
        else
          options = options.dup
        end
        options[:version] ||= 3
        @options = options
        if @connection = @options.delete(:connection)
          begin
            host, port = @connection.get_option(::LDAP::LDAP_OPT_HOST_NAME).split(':')
            @options[:host] ||= host
            @options[:port] ||= port.to_i if port
          rescue
          end
        else
          if username = @options.delete(:username)
            @options[:username] = full_username(username)
          end
          if @options[:username]
            connection = new_connection
            bind_connection(connection, @options[:username], @options[:password])
            connection.unbind
          end
        end
        @logger = @options.delete(:logger)
        super(@options)
      end

      def add(dn, attributes)
        with_writer do |conn|
          conn.add(dn, attributes)
        end
      end

      def modify(dn, attributes)
        if attributes.kind_of?(Array)
          attributes = attributes.map do |(op, key, vals)|
            LDAP::Mod.new(mod(op) | LDAP::LDAP_MOD_BVALUES, key, vals)
          end
        end
        with_writer do |conn|
          conn.modify(dn, attributes)
        end
      end

      def delete(dn)
        with_writer do |conn|
          conn.delete(dn)
        end
      end

      def rename(dn, new_rdn, delete_old, new_superior = nil)
        with_writer do |conn|
          if new_superior
            # This is from a patch I hope to get accepted upstream.
            if conn.respond_to?(:rename)
              conn.rename(dn, new_rdn, new_superior, delete_old)
            else
              Ldaptic::Errors.raise(NotImplementedError.new("rename unsupported"))
            end
          else
            conn.modrdn(dn, new_rdn, delete_old)
          end
        end
      end

      def compare(dn, attr, value)
        with_reader do |conn|
          conn.compare(dn, attr, value)
        end
      rescue Ldaptic::Errors::CompareFalse
        false
      rescue Ldaptic::Errors::CompareTrue
        true
      end

      def search(options = {}, &block)
        parameters = search_parameters(options)
        with_reader do |conn|
          begin
            if options[:limit]
              # Some servers don't support this option.  If that happens, the
              # higher level interface will simulate it.
              conn.set_option(LDAP::LDAP_OPT_SIZELIMIT, options[:limit]) rescue nil
            end
            cookie = ""
            while cookie
              ctrl = paged_results_control(cookie)
              if !options[:disable_pagination] && paged_results?
                conn.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS, [ctrl])
              end
              params = parameters
              result = conn.search2(*params, &block)
              ctrl   = conn.controls.detect {|c| c.oid == ctrl.oid}
              cookie = ctrl && ctrl.decode.last
              cookie = nil if cookie.to_s.empty?
            end
          ensure
            conn.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS, []) rescue nil
            conn.set_option(LDAP::LDAP_OPT_SIZELIMIT, 0) rescue nil
          end
        end
      end

      def authenticate(dn, password)
        conn = new_connection
        bind_connection(conn, full_username(dn) || "", password)
        true
      rescue ::LDAP::ResultError => exception
        message = exception.message
        err = error_for_message(message)
        unless err == 49 # Invalid credentials
          Ldaptic::Errors.raise_unless_zero(err, message)
        end
        false
      ensure
        conn.unbind rescue nil
      end

      def default_base_dn
        @options[:base] || server_default_base_dn
      end

      private

      def paged_results?
        if @paged_results.nil?
          @paged_results = root_dse('supportedControl').to_a.include?(CONTROL_PAGEDRESULTS)
        end
        @paged_results
      end

      # ::LDAP::LDAP_CONTROL_PAGEDRESULTS,
      CONTROL_PAGEDRESULTS = "1.2.840.113556.1.4.319"

      def paged_results_control(cookie = "", size = 126)
        require 'ldap/control'
        # values above 126 cause problems for slapd, as determined by net/ldap
        ::LDAP::Control.new(
          CONTROL_PAGEDRESULTS,
          ::LDAP::Control.encode(size, cookie),
          true
        )
      end

      def search_parameters(options = {})
        [
          options[:base],
          options[:scope],
          options[:filter],
          options[:attributes] && Array(options[:attributes]),
          options[:attributes_only],
          options[:timeout].to_i,
          ((options[:timeout].to_f % 1) * 1e6).round,
        ]
      end

      def new_connection(default_port = nil)
        if @options[:tls].nil?
          conn = ::LDAP::Conn.new(
            @options[:host]||"localhost",
            *[@options[:port] || default_port].compact
          )
        else
          conn = ::LDAP::SSLConn.new(
            @options[:host]||"localhost",
            @options[:port] || default_port || ::LDAP::LDAP_PORT,
            @options[:tls]
          )
        end
        conn.set_option(::LDAP::LDAP_OPT_PROTOCOL_VERSION, @options[:version])
        conn
      end

      def bind_connection(conn, dn, password, &block)
        if dn
          password = password.call if password.respond_to?(:call)
          conn.bind(dn, password, *[@options[:method]].compact, &block)
        else
          block_given? ? yield(conn) : conn
        end
      end

      def full_username(username)
        if username.kind_of?(Hash)
          base = Ldaptic::DN(default_base_dn || "")
          base / username
        else
          username
        end
      end

      def with_reader(&block)
        if @connection
          with_conn(@connection, &block)
        else
          conn = new_connection
          bind_connection(conn, @options[:username], @options[:password]) do
            with_conn(conn, &block)
          end
        end
      end

      alias with_writer with_reader

      def with_conn(conn, &block)
        err, message, result = 0, nil, nil
        begin
          result = yield conn
        rescue ::LDAP::ResultError => exception
          message = exception.message
          err = error_for_message(message)
        end
        conn_err = conn.err.to_i
        if err.zero? && !conn_err.zero?
          err = conn_err
          message = conn.err2string(err) rescue nil
        end
        Ldaptic::Errors.raise_unless_zero(err, message)
        result
      end

      # LDAP::Conn only gives us a worthless string rather than a real error
      # code on exceptions.
      def error_for_message(msg)
        unless @errors
          with_reader do |conn|
            @errors = (0..127).inject({}) do |h, err|
              h[conn.err2string(err)] = err; h
            end
          end
          @errors.delete("Unknown error")
        end
        @errors[msg]
      end

      def mod(symbol)
        {
          :add     => LDAP::LDAP_MOD_ADD,
          :replace => LDAP::LDAP_MOD_REPLACE,
          :delete  => LDAP::LDAP_MOD_DELETE
        }[symbol]
      end

    end
  end
end

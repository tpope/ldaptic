require 'ldapter/adapters/abstract_adapter'

module Ldapter
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
        if @connection = @options[:connection]
          begin
            host, port = @connection.get_option(::LDAP::LDAP_OPT_HOST_NAME).split(':')
            @options[:host] ||= host
            @options[:port] ||= port.to_i if port
          rescue
          end
        else
          if @options[:username].kind_of?(Hash)
            rdn = @options.delete(:username)
            base = LDAP::DN(default_base_dn || "")
            @options[:username] = base / rdn
          end
          if @options[:username]
            connection = new_connection
            bind_connection(connection,@options[:username],@options[:password])
            connection.unbind
          end
          # @connection = @options[:connection] = connection
        end
        @logger     = @options[:logger]
      end

      def add(dn, attributes)
        with_writer do |conn|
          conn.add(dn, attributes)
        end
      end

      def modify(dn, attributes)
        if attributes.kind_of?(Array)
          attributes = attributes.map do |(op,key,vals)|
            # if vals.any? {|v| v =~ /[\000-\037]/}
              bin = LDAP::LDAP_MOD_BVALUES
            # else
              # bin = 0
            # end
            LDAP::Mod.new(mod(op) | bin, key, vals)
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
              Ldapter::Errors.raise(NotImplementedError.new("rename unsupported"))
            end
          else
            conn.modrdn(dn,new_rdn, delete_old)
          end
        end
      end

      def search(options = {}, &block)
        parameters = search_parameters(options)
        with_reader do |conn|
          begin
            if options[:limit]
              # Some servers don't support this option.  If that happens, the
              # higher level interface will simulate it.
              conn.set_option(LDAP::LDAP_OPT_SIZELIMIT,options[:limit]) rescue nil
            end
            cookie = ""
            while cookie
              ctrl = paged_results_control(cookie)
              conn.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS,[ctrl])
              params = parameters
              # params = parameters[0,5] + [[ctrl],[],50] + parameters[5..-1]
              result = conn.search2(*params, &block)
              ctrl   = conn.controls.detect {|c| c.oid == ctrl.oid}
              cookie = ctrl && ctrl.decode.last
              cookie = nil if cookie.to_s.empty?
            end
          ensure
            conn.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS,[]) rescue nil
            conn.set_option(LDAP::LDAP_OPT_SIZELIMIT,0) rescue nil
          end
        end
      end

      def authenticate(dn, password)
        conn = new_connection
        bind_connection(conn, dn || "", password)
        true
      rescue ::LDAP::ResultError => exception
        message = exception.message
        err = error_for_message(message)
        unless err == 49 # Invalid credentials
          Ldapter::Errors.raise_unless_zero(err, message)
        end
        false
      ensure
        conn.unbind rescue nil
      end

      def default_base_dn
        @options[:base] || server_default_base_dn
      end

      private

      def paged_results_control(cookie = "", size = 126)
        require 'ldap/control'
        # values above 126 cause problems for slapd, as determined by net/ldap
        ::LDAP::Control.new(
          # ::LDAP::LDAP_CONTROL_PAGEDRESULTS,
          "1.2.840.113556.1.4.319",
          ::LDAP::Control.encode(size,cookie),
          true
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

      def with_reader(&block)
        if @connection
          with_conn(@connection,&block)
        else
          conn = new_connection
          bind_connection(conn,@options[:username],@options[:password]) do
            with_conn(conn,&block)
          end
        end
      end

      alias with_writer with_reader

      def with_conn(conn,&block)
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
        Ldapter::Errors.raise_unless_zero(err, message)
        result
      end

      # LDAP::Conn only gives us a worthless string rather than a real error
      # code on exceptions.
      def error_for_message(msg)
        unless @errors
          with_reader do |conn|
            @errors = (0..127).inject({}) do |h,err|
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

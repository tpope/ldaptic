require 'ldapter/adapters/ldap_conn_adapter'

module Ldapter
  module Adapters
    # ActiveDirectoryAdapter is a LDAPConnAdapter with some Active Directory
    # specific behaviors.  To help mitigate server timeout issues, this adapter
    # binds on each request and unbinds afterwards.  For search requests, the
    # adapter connects to the global catalog on port 3268 instead of the usual
    # port 389.  The global catalog is read-only but is a bit more flexible
    # when it comes to searching.
    #
    # Active Directory servers can also be connected to with the Net::LDAP
    # adapter.
    class ActiveDirectoryAdapter < LDAPConnAdapter
      register_as(:active_directory)

      def initialize(options)
        super
        @connection.unbind
        @options[:connection] = @connection = nil
      end

      def authenticate(dn, password)
        super(full_username(dn), password)
      end

      private

      def full_username(username = @options[:username])
        if username !~ /[\\=@]/
          if @options[:domain].include?(".")
            username = [username,@options[:domain]].compact.join("@")
          else
            username = [@options[:domain],username].compact.join("\\")
          end
        end
        username
      end

      def with_port(port,&block)
        conn = new_connection(port)
        bind_connection(conn,full_username,@options[:password])
        with_conn(conn,&block)
      ensure
        conn.unbind rescue nil
      end

      def with_reader(&block)
        with_port(3268,&block)
      end

      def with_writer(&block)
        with_port(389,&block)
      end

    end
  end
end

require 'ldaptic/adapters/ldap_conn_adapter'
require 'ldaptic/adapters/active_directory_ext'

module Ldaptic
  module Adapters
    # Before using this adapter, try the :ldap_conn adapter.  The notes below
    # were originally thought to apply to all Active Directory servers, but now
    # I suspect they are peculiarities of a former employer's setup.  This
    # adapter is a candidate for removal.
    #
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
        if @connection
          @options[:connection] = @connection = nil
        end
      end

      # Returns either the +defaultNamingContext+ (Active Directory specific)
      # or the first of the +namingContexts+ found in the RootDSE.
      def server_default_base_dn
        unless defined?(@naming_contexts)
          @naming_contexts = root_dse(%w(defaultNamingContext namingContexts))
        end
        if @naming_contexts
          @naming_contexts["defaultNamingContext"].to_a.first ||
            @naming_contexts["namingContexts"].to_a.first
        end
      end

      private

      def full_username(username)
        if username.kind_of?(Hash)
          super
        elsif username && username !~ /[\\=@]/
          if @options[:domain].include?(".")
            username = [username, @options[:domain]].join("@")
          elsif @options[:domain]
            username = [@options[:domain], username].join("\\")
          else
            conn = new_connection(3268)
            dn = conn.search2("", 0, "(objectClass=*)", ['defaultNamingContext']).first['defaultNamingContext']
            if dn
              domain = Ldaptic::DN(dn).rdns.map {|rdn| rdn[:dc]}.compact
              unless domain.empty?
                username = [username, domain.join(".")].join("@")
              end
            end
          end
        end
        username
      end

      def with_port(port, &block)
        conn = new_connection(port)
        bind_connection(conn, @options[:username], @options[:password]) do
          with_conn(conn, &block)
        end
      end

      def with_reader(&block)
        with_port(3268, &block)
      end

      def with_writer(&block)
        with_port(@options[:port] || 389, &block)
      end

    end
  end
end

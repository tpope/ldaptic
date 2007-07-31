module Ldapter
  # RFC1823 - The LDAP Application Program Interface
  module Adapters

    @adapters ||= {}

    class <<self

      # Internally used by adapters to make themselves available.
      def register(name, mod) #:nodoc:
        @adapters[name.to_sym] = mod
        @adapters
      end

      # Returns a new adapter for a given set of options.  This method is not
      # for end user use but is instead called by the Ldapter::Class,
      # Ldapter::Module, and Ldapter::Object methods.
      #
      # The <tt>:adapter</tt> key of the +options+ hash selects which adapter
      # to use.  The following adapters are included with Ldapter.
      #
      # * <tt>:ldap_conn</tt>: a Ruby/LDAP LDAP::Conn connection.
      # * <tt>:ldap_sslconn</tt>: a Ruby/LDAP LDAP::SSLConn connection.
      # * <tt>:active_directory</tt>: A wrapper around Ruby/LDAP which takes
      #   into account some of the idiosyncrasies of Active Directory.
      # * <tt>:net_ldap</tt>: a ruby-net-ldap Net::LDAP connection.
      #
      # All other options given are passed directly to the adapter.  While
      # different adapters support different options, the following are
      # typically supported.
      #
      # * <tt>:host</tt>: The host to connect to.  The default is localhost.
      # * <tt>:port</tt>: The TCP port to use.  Default is provided by the
      #   underlying connection.
      # * <tt>:username</tt>: The DN to bind with.  If not given, an anonymous
      #   bind is used.
      # * <tt>:password</tt>: Password for binding.
      # * <tt>:base</tt>: The default base DN.  Derived from the server by
      #   default.
      def for(options)
        require 'ldapter/adapters/abstract_adapter'
        # Allow an adapter to be passed directly in for backwards compatibility.
        if defined?(::LDAP::Conn) && options.kind_of?(::LDAP::Conn)
          options = {:adapter => :ldap_conn, :connection => options}
        elsif defined?(::Net::LDAP) && options.kind_of?(::Net::LDAP)
          options = {:adapter => :net_ldap, :connection => options}
        end
        if options.kind_of?(Hash)
          options = options.inject({}) {|h,(k,v)| h[k.to_sym] = v; h}
          if options.has_key?(:connection) && !options.has_key?(:adapter)
            options[:adapter] = options[:connection].class.name.downcase.gsub('::','_')
          end
          options[:adapter] ||= default_adapter
          unless options[:adapter]
            Ldapter::Errors.raise(ArgumentError.new("No adapter specfied"))
          end
          begin
            require "ldapter/adapters/#{options[:adapter]}_adapter"
          rescue LoadError
          end
          if adapter = @adapters[options[:adapter].to_sym]
            adapter.new(options)
          else
            Ldapter::Errors.raise(ArgumentError.new("Adapter #{options[:adapter]} not found"))
          end
        else
          if options.kind_of?(::Ldapter::Adapters::AbstractAdapter)
            options
          else
            Ldapter::Errors.raise(TypeError.new("#{options.class} is not a valid connection type"))
          end
        end
      end

      private
      def default_adapter
        require 'ldap'
        :ldap_conn
      rescue LoadError
        begin
          require 'net/ldap'
          :net_ldap
        rescue LoadError
        end
      end

    end

  end
end

require 'ldapter/adapters/abstract_adapter'

module Ldapter
  module Adapters
    class NetLDAPAdapter < AbstractAdapter

      register_as(:net_ldap)

      def initialize(options)
        require 'ldapter/adapters/net_ldap_ext'
        if defined?(::Net::LDAP) && options.kind_of?(::Net::LDAP)
          options = {:adapter => :net_ldap, :connection => option}
        else
          options = (options || {}).dup
        end
        if connection = options[:connection]
          auth       = connection.instance_variable_get(:@auth) || {}
          encryption = connection.instance_variable_get(:@encryption)
          options = {
            :adapter => :net_ldap,
            :host => connection.host,
            :port => connection.port,
            :base => connection.base == "dc=com" ? nil : connection.base,
            :username => auth[:username],
            :password => auth[:password]
          }.merge(options)
          if encryption
            options[:encryption] ||= encryption
          end
        else
          options[:connection] ||= ::Net::LDAP.new(
            :host => options[:host],
            :port => options[:port],
            :encryption => options[:encryption],
            :auth => {:method => :simple, :username => options[:username], :password => options[:password]}
          )
        end
        @options    = options
        @connection = options[:connection]
        @logger     = options[:logger]
      end

      attr_reader :connection

      def add(dn, attributes)
        connection.add(:dn => dn, :attributes => attributes)
        handle_errors
      end

      def modify(dn, attributes)
        connection.modify(
          :dn => dn,
          :operations => attributes.map {|k,v| [:replace, k, v]}
        )
        handle_errors
      end

      def delete(dn)
        connection.delete(:dn => dn)
        handle_errors
      end

      def rename(dn, new_rdn, delete_old, new_superior = nil)
        connection.rename(:olddn => dn, :newrdn => new_rdn, :delete_attributes => delete_old, :newsuperior => new_superior)
        handle_errors
      end

      DEFAULT_CAPITALIZATIONS = %w[
        objectClass

        objectClasses
        attributeTypes
        matchingRules
        matchingRuleUse
        dITStructureRules
        dITContentRules
        nameForms
        ldapSyntaxes

        configurationNamingContext
        currentTime
        defaultNamingContext
        dn
        dnsHostName
        domainControllerFunctionality
        domainFunctionality
        dsServiceName
        forestFunctionality
        highestCommittedUSN
        isGlobalCatalogReady
        isSynchronized
        ldapServiceName
        namingContexts
        rootDomainNamingContext
        schemaNamingContext
        serverName
        subschemaSubentry
        supportedCapabilities
        supportedControl
        supportedLDAPPolicies
        supportedLDAPVersion
        supportedSASLMechanisms
      ].inject({}) { |h,k| h[k.downcase] = k; h }

      def search(options = {}, &block)
        options = options.merge(:return_result => false)
        connection.search(options) do |entry|
          hash = {}
          entry.each do |attr,val|
            attr = recapitalize(attr)
            hash[attr] = val
          end
          block.call(hash)
        end
        handle_errors
      end

      # Convenience method which returns true if the credentials are valid, and
      # false otherwise.  The credentials are discarded afterwards.
      def authenticate(dn, password)
        conn = Net::LDAP.new(
          :host => @options[:host],
          :port => @options[:port],
          :encryption => @options[:encryption],
          :auth => {:method => :simple, :username => dn, :password => password}
        )
        conn.bind
      end

      def default_base_dn
        @options[:base] || server_default_base_dn
      end

      def inspect
        "#<#{self.class} #{@connection.inspect}>"
      end

      private
      def recapitalize(attribute)
        attribute = attribute.to_s
        @cached_capitalizations ||= DEFAULT_CAPITALIZATIONS
        caps = @cached_capitalizations[attribute] ||=
          attribute_types.keys.detect do |x|
            x.downcase == attribute.downcase
          end
        if caps
          caps
        else
          logger.warn('ldapter') { "#{attribute} could not be capitalized" }
          @cached_capitalizations[attribute] = attribute
        end
      end

      def handle_errors
        result = yield if block_given?
        err = @connection.get_operation_result
        Ldapter::Errors.raise_unless_zero(err.code, err.message)
        result
      end

    end

  end
end

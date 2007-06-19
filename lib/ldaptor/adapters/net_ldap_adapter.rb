require 'ldaptor/adapters/abstract_adapter'

module Ldaptor
  module Adapters
    class NetLDAPAdapter < AbstractAdapter

      register_as(:net_ldap)

      def initialize(options)
        require 'net/ldap'
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
        @options = options
        @connection = options[:connection]
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

      def rename(dn, new_rdn, delete_old)
        connection.rename(:olddn => dn, :newrdn => new_rdn, :delete_attributes => delete_old)
        handle_errors
      end

      DEFAULT_CAPITALIZATIONS = %w[
        dn
        objectClass
        subschemaSubentry
        namingContexts
        monitorContext
        altServer
        supportedControl
        supportedExtension
        supportedFeatures
        supportedSASLMechanisms
        supportedLDAPVersion
        defaultNamingContext
        objectClasses
        attributeTypes
        matchingRules
        matchingRuleUse
        dITStructureRules
        dITContentRules
        nameForms
        ldapSyntaxes
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
        @cached_capitalizations ||= DEFAULT_CAPITALIZATIONS
        @cached_capitalizations[attribute.to_s] ||=
          attribute_types.keys.detect do |x|
            x.downcase == attribute.to_s.downcase
          end
      end

      def handle_errors
        result = yield if block_given?
        err = @connection.get_operation_result
        Ldaptor::Errors.raise_unless_zero(err.code, err.message)
        result
      end

    end

  end
end

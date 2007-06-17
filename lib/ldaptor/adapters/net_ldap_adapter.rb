require 'ldaptor/adapters/abstract_adapter'

module Ldaptor
  module Adapters
    class NetLDAPAdapter < AbstractAdapter

      def add(dn,attr)
        @connection.add(:dn => dn, :attributes => attr)
      end

      def modify(dn, attributes)
        @connection.modify(
          :dn => dn,
          :operations => attributes.map {|k,v| [:replace, k, v]}
        )
      end

      def delete(dn)
        @connection.delete(:dn => dn)
      end

      DEFAULT_TRANSFORMATIONS = %w[
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
        options = search_options(options).merge(:return_result => false)
        @connection.search(options) do |entry|
          hash = {}
          entry.each do |attr,val|
            attr = recapitalize(attr)
            hash[attr] = val
          end
          block.call(hash)
        end
        nil
      end

      private
      def recapitalize(attribute)
        DEFAULT_TRANSFORMATIONS[attribute.to_s] ||
          attribute_types.keys.detect do |x|
            x.downcase == attribute.to_s.downcase
          end
      end

    end
  end
end

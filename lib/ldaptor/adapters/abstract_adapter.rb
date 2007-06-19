require 'ldap/escape'
require 'ldaptor/errors'

module Ldaptor
  module Adapters
    # Subclasse must implement search, add, modify, delete, and rename.  These
    # methods should return 0 on success and non-zero on failure.  The failure
    # code is intended to be the server error code.  If this is unavailable,
    # return -1.
    class AbstractAdapter

      # When implementing an adapter, +register_as+ must be called to associate
      # the adapter with a name.  The adapter name must mimic the filename.
      # The following might be found in ldaptor/adapters/some_adapter.rb.
      #
      #   class SomeAdapter < AbstractAdapter
      #     register_as(:some)
      #   end
      def self.register_as(name)
        require 'ldaptor/adapters'
        Ldaptor::Adapters.register(name, self)
      end

      def initialize(options)
        @options = options
      end

      # The server's RootDSE.  +attrs+ is an array specifying which attributes
      # to return.
      def root_dse(attrs = nil)
        attrs ||= %w[
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
        ]
        result = search(
          :base => "",
          :scope => Ldaptor::SCOPES[:base],
          :filter => "(objectClass=*)",
          :attributes => Array(attrs).map {|a| LDAP.escape(a)}
        ) { |x| break x }
        return nil if result.kind_of?(Fixnum)
        if attrs.kind_of?(Array)
          result
        else
          result[attrs]
        end
      end

      def schema(attrs = nil)
        attrs ||= %w[
          objectClass
          objectClasses
          attributeTypes
          matchingRules
          matchingRuleUse
          dITStructureRules
          dITContentRules
          nameForms
          ldapSyntaxes
        ]
        search(
          :base => root_dse(['subschemaSubentry'])['subschemaSubentry'].first,
          :scope => Ldaptor::SCOPES[:base],
          :filter => "(objectClass=subSchema)",
          :attributes => attrs
        ) { |x| return x }
        nil
      end

      # Returns either the +defaultNamingContext+ (Active Directory specific)
      # or the first of the +namingContexts+ found in the RootDSE.
      def server_default_base_dn
        result = root_dse(%w(defaultNamingContext namingContexts))
        if result
          result["defaultNamingContext"].to_a.first ||
            result["namingContexts"].to_a.first
        end
      end

      alias default_base_dn server_default_base_dn

      # Returns a hash of attribute types, keyed by both OID and name.
      def attribute_types
        @attribute_types ||= construct_schema_hash('attributeTypes',
          Ldaptor::Schema::AttributeType)
      end

      # Returns a hash of DIT content rules, keyed by both OID and name.
      def dit_content_rules
        @dit_content_rules ||= construct_schema_hash('dITContentRules',
          Ldaptor::Schema::DITContentRule)
      end

      # Returns a hash of object classes, keyed by both OID and name.
      def object_classes
        @object_classes ||= construct_schema_hash('objectClasses',
          Ldaptor::Schema::ObjectClass)
      end

      private

      def construct_schema_hash(element,klass)
        @schema_hash ||= schema(['attributeTypes','dITContentRules','objectClasses'])
        @schema_hash[element.to_s].inject({}) do |hash,val|
          object = klass.new(val)
          hash[object.oid] = object
          Array(object.name).each do |name|
            hash[name] = object
          end
          hash
        end
      end

    end
  end
end

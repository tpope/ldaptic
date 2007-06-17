module Ldaptor
  module Adapters
    class AbstractAdapter

      def initialize(options)
        @options = options
      end

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
          :scope => :base,
          :filter => "(objectClass=*)",
          :attributes => Array(attrs)
        ) { |x| break x }
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
          :scope => :base,
          :filter => "(objectClass=subSchema)",
          :attributes => attrs
        ) { |x| break x }
      end

      def attribute_types
        @attribute_types ||= schema(['attributeTypes'])['attributeTypes'].inject({}) do |hash,val|
          at = Ldaptor::Schema::AttributeType.new(val)
          hash[at.oid] = at
          Array(at.name).each do |name|
            hash[name] = at
          end
          hash
        end
        @attribute_types
      end

      def dit_content_rules
        @dit_content_rules ||= schema(['dITContentRules'])['dITContentRules'].inject({}) do |hash,val|
          dit = Ldaptor::Schema::DITContentRule.new(val)
          hash[dit.oid] = dit
          Array(dit.name).each do |name|
            hash[name] = dit
          end
          hash
        end
      end

      def object_classes
        @object_classes ||= schema(['objectClasses'])['objectClasses'].inject({}) do |hash,val|
          ocl = Ldaptor::Schema::ObjectClass.new(val)
          hash[ocl.oid] = ocl
          Array(ocl.name).each do |name|
            hash[name] = ocl
          end
          hash
        end
      end

      def server_default_base_dn
        result = root_dse(%w(defaultNamingContext namingContexts))
        if result
          result["defaultNamingContext"].to_a.first ||
            result["namingContexts"].to_a.first
        end
      end

      def search_options(options = {})
        options = options.dup
        options[:scope] = ::Ldaptor::SCOPES[options[:scope]] || options[:scope] || ::Ldaptor::SCOPES[:subtree]
        if options[:attributes].respond_to?(:to_ary)
          options[:attributes] = options[:attributes].map {|x| LDAP.escape(x)}
        elsif options[:attributes]
          options[:attributes] = LDAP.escape(options[:attributes])
        end
        query = options[:filter]
        query = {:objectClass => :*} if query.nil?
        query = LDAP::Filter(query)
        options[:filter] = query
        options
      end

      def self.register_as(name)
        require 'ldaptor/adapters'
        Ldaptor::Adapters.register(name, self)
      end

      # search, add, modify, rename
    end
  end
end

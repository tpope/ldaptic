module Ldaptor
  module Adapters
    class AbstractAdapter

      def initialize(connection)
        @connection = connection
      end

      def root_dse(attrs = nil) # Namespace
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

      def schema(attrs = nil) # Namespace
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

      # search, add, modify, rename
    end

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
            attr = DEFAULT_TRANSFORMATIONS[attr.to_s] ||
              attribute_types.keys.detect do |x|
              x.downcase == attr.to_s.downcase
              # break(x.name) if x.names.map {|n|n.downcase}.include?(attr.to_s)
              end
            hash[attr.to_s] = val
          end
          block.call(hash)
        end
        nil
      end

    end

    class LDAPAdapter < AbstractAdapter

      def add(dn, attributes)
        @connection.add(dn, attributes)
      end

      def modify(dn, attributes)
        @connection.modify(dn, attributes)
      end

      def delete(dn)
        @connection.delete(dn)
      end

      def rename(dn, new_rdn, delete_old)
        @connection.modrdn(dn,new_rdn, delete_old)
      end

      def search(options = {}, &block)
        cookie = ""
        options = search_options(options)
        parameters = search_parameters(options)
        while cookie
          ctrl = paged_results_control(cookie)
          @connection.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS,[ctrl])
          result = @connection.search2(*parameters, &block)
          ctrl = @connection.controls.detect {|c| c.oid == ctrl.oid}
          cookie = ctrl && ctrl.decode.last
          cookie = nil if cookie.to_s.empty?
        end
      ensure
        @connection.set_option(LDAP::LDAP_OPT_SERVER_CONTROLS,[]) rescue nil
      end

      private
      def paged_results_control(cookie = "", size = 126) # Namespace
        # values above 126 cause problems for slapd, as determined by net/ldap
        ::LDAP::Control.new(
          # ::LDAP::LDAP_CONTROL_PAGEDRESULTS,
          "1.2.840.113556.1.4.319",
          ::LDAP::Control.encode(size,cookie),
          false
        )
      end

      def search_parameters(options = {}) # Namespace
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

    end

  end
end

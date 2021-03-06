require 'ldaptic/escape'
require 'ldaptic/errors'

module Ldaptic
  module Adapters
    # Subclasse must implement search, add, modify, delete, and rename.  These
    # methods should return 0 on success and non-zero on failure.  The failure
    # code is intended to be the server error code.  If this is unavailable,
    # return -1.
    class AbstractAdapter

      # When implementing an adapter, +register_as+ must be called to associate
      # the adapter with a name.  The adapter name must mimic the filename.
      # The following might be found in ldaptic/adapters/some_adapter.rb.
      #
      #   class SomeAdapter < AbstractAdapter
      #     register_as(:some)
      #   end
      def self.register_as(name)
        require 'ldaptic/adapters'
        Ldaptic::Adapters.register(name, self)
      end

      def initialize(options)
        @options = options
      end

      # The server's RootDSE.  +attrs+ is an array specifying which attributes
      # to return.
      def root_dse(attrs = nil)
        result = search(
          :base => "",
          :scope => Ldaptic::SCOPES[:base],
          :filter => "(objectClass=*)",
          :attributes => attrs && [attrs].flatten.map {|a| Ldaptic.encode(a)},
          :disable_pagination => true
        ) { |x| break x }
        return if result.kind_of?(Fixnum)
        if attrs.kind_of?(Array) || attrs.nil?
          result
        else
          result[attrs]
        end
      end

      def schema(attrs = nil)
        @subschema_dn ||= root_dse(['subschemaSubentry'])['subschemaSubentry'].first
        search(
          :base => @subschema_dn,
          :scope => Ldaptic::SCOPES[:base],
          :filter => "(objectClass=subschema)",
          :attributes => attrs
        ) { |x| return x }
        nil
      end

      # Returns the first of the +namingContexts+ found in the RootDSE.
      def server_default_base_dn
        unless defined?(@naming_contexts)
          @naming_contexts = root_dse(%w(namingContexts))
        end
        if @naming_contexts
          @naming_contexts["namingContexts"].to_a.first
        end
      end

      alias default_base_dn server_default_base_dn

      # Returns a hash of attribute types, keyed by both OID and name.
      def attribute_types
        @attribute_types ||= construct_schema_hash('attributeTypes',
          Ldaptic::Schema::AttributeType)
      end

      def attribute_type(key = nil)
        if key
          attribute_types[key] || attribute_types.values.detect do |at|
            at.names.map {|n| n.downcase}.include?(key.downcase)
          end
        else
          attribute_types.values.uniq
        end
      end

      # Returns a hash of DIT content rules, keyed by both OID and name.
      def dit_content_rules
        @dit_content_rules ||= construct_schema_hash('dITContentRules',
          Ldaptic::Schema::DITContentRule)
      end

      # Returns a hash of object classes, keyed by both OID and name.
      def object_classes
        @object_classes ||= construct_schema_hash('objectClasses',
          Ldaptic::Schema::ObjectClass)
      end

      # Default compare operation, emulated with a search.
      def compare(dn, attr, value)
        search(:base => dn, :scope => Ldaptic::SCOPES[:base], :filter => "(#{attr}=#{Ldaptic.escape(value)})") { return true }
        false
      end

      def logger
        @logger || Ldaptic.logger
      end

      private

      def construct_schema_hash(element, klass)
        @schema_hash ||= schema(['attributeTypes', 'dITContentRules', 'objectClasses'])
        @schema_hash[element.to_s].to_a.inject({}) do |hash, val|
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

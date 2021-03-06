module Ldaptic
  # RFC4512 - LDAP: Directory Information Models
  module Schema

    class ParseError < RuntimeError
    end

    class AbstractDefinition

      class << self
        def attr_ldap_boolean(*attrs)
        attrs.each do |attr|
          class_eval(<<-EOS)
            def #{attr}?
              !!attributes[:#{attr}]
            end
          EOS
        end
      end

        def attr_ldap_reader(*attrs)
          attrs.each do |attr|
            class_eval(<<-EOS)
              def #{attr}
                attributes[:#{attr}]
              end
            EOS
          end
        end

        alias attr_ldap_qdstring   attr_ldap_reader
        alias attr_ldap_qdescr     attr_ldap_reader
        alias attr_ldap_qdescrs    attr_ldap_reader
        alias attr_ldap_oid        attr_ldap_reader
        alias attr_ldap_oids       attr_ldap_reader
        alias attr_ldap_noidlen    attr_ldap_reader
        alias attr_ldap_numericoid attr_ldap_reader
      end

      attr_accessor :oid
      attr_reader   :attributes

      def inspect
        "#<#{self.class.inspect} #{@oid} #{attributes.inspect}>"
      end

      def to_s
        @string
      end

      def initialize(string)
        @string = string.dup
        string = @string.dup
        @oid = extract_oid(string)
        array = build_array(string.dup)
        hash = array_to_hash(array)
        @attributes = hash
      end

      private

      def extract_oid(string)
        string.gsub!(/^\s*\(\s*(\w[\w:.-]*\w)\s*(.*?)\s*\)\s*$/, '\\2')
        $1
      end

      def build_array(string)
        array = []
        until string.empty?
          if string =~ /\A(\(\s*)?'/
            array << eatstr(string)
          elsif string =~ /\A[A-Z-]+[A-Z]\b/
            array << eat(string, /\A[A-Z0-9-]+/).downcase.gsub('-', '_').to_sym
          elsif string =~ /\A(\(\s*)?[\w-]/
            array << eatary(string)
          else
            raise ParseError
          end
        end
        array
      rescue ParseError
        raise ParseError, "failed to parse schema entry #{@string.inspect}", caller[1..-1]
      end

      def array_to_hash(array)
        last = nil
        hash = {}
        array.each do |elem|
          if elem.kind_of?(Symbol)
            hash[last] = true if last
            last = elem
          else
            if last
              hash[last] = elem
              last = nil
            else
              raise ParseError, "failed to parse schema entry #{@string.inspect}", caller[1..-1]
            end
          end
        end
        hash[last] = true if last
        hash
      end

      def eat(string, regex)
        string.gsub!(regex, '')
        string.strip!
        $1 || $&
      end

      def eatstr(string)
        if eaten = eat(string, /^\(\s*'([^)]+)'\s*\)/i)
          eaten.split("' '").collect{|attr| attr.strip }
        else
          eat(string, /^'([^']*)'\s*/)
        end
      end

      def eatary(string)
        if eaten = eat(string, /^\(([\w\d_.{}\s\$-]+)\)/i)
          eaten.split("$").collect{|attr| attr.strip}
        elsif eaten = eat(string, /^([\w\d_.{}-]+)/i)
          eaten
        else
          raise ParseError
        end
      end

      def method_missing(key, *args, &block)
        if key.to_s =~ /^x_.*[^!=]$/
          if args.size == 0
            if key.to_s[-1] == ??
              !!attributes[key.to_s[0..-2].to_sym]
            else
              attributes[key]
            end
          else
            raise ArgumentError, "wrong number of arguments (#{args.size} for 0)", caller
          end
        else
          super(key, *args, &block)
        end
      end

    end

    # Serves as an abstract base class for the many definitions that feature
    # +name+, +desc+, and +obsolete+ attributes.
    class NameDescObsoleteDefiniton < AbstractDefinition
      attr_ldap_qdescrs    :name
      attr_ldap_qdstring   :desc
      attr_ldap_boolean    :obsolete

      # The definition's name(s), always returned as an array for programmatic
      # ease.
      def names
        Array(name)
      end

      # The longest (and hopefully most descriptive) name.  Used by
      # +human_attribute_name+.
      def verbose_name
        names.sort_by { |n| n.size }.last
      end

    end

    class ObjectClass < NameDescObsoleteDefiniton
      attr_ldap_oids       :sup
      attr_ldap_boolean    :structural, :auxiliary, :abstract
      attr_ldap_oids       :must, :may
      # "ABSTRACT", "STRUCTURAL", or "AUXILIARY"
      def kind
        if abstract?
          "ABSTRACT"
        elsif structural?
          "STRUCTURAL"
        elsif auxiliary?
          "AUXILIARY"
        end
      end
    end

    class AttributeType < NameDescObsoleteDefiniton
      attr_ldap_oid        :sup, :equality, :ordering, :substr
      attr_ldap_noidlen    :syntax
      attr_ldap_boolean    :single_value, :collective, :no_user_modification
      attr_ldap_qdescr     :usage  # attr_ldap_usage

      def syntax_attribute
        @attributes[:syntax]
      end
      def syntax_oid
        syntax_attribute && syntax_attribute[/[0-9.]+/]
      end
      def syntax_len
        syntax_attribute && syntax_attribute[/\{(.*)\}/, 1].to_i
      end
      def syntax_object(*args)
        Ldaptic::SYNTAXES[syntax_oid]
      end
      alias syntax syntax_object

      def matchable(value)
        Ldaptic::MatchingRules.for(equality).new.matchable(Ldaptic.encode(value))
      end

    end

    class MatchingRule < NameDescObsoleteDefiniton
      attr_ldap_numericoid :syntax # mandatory
    end

    class MatchingRuleUse < NameDescObsoleteDefiniton
      attr_ldap_oids       :applies # mandatory
    end

    # Note that LDAP syntaxes do not have names or the obsolete flag, only
    # desc[riptions].
    class LdapSyntax < AbstractDefinition
      attr_ldap_qdstring   :desc

      # Returns the appropriate parser from the Ldaptic::Syntaxes module.
      def object
        Ldaptic::Syntaxes.for(desc.delete(" "))
      end
    end

    class DITContentRule < NameDescObsoleteDefiniton
      attr_ldap_oids       :aux, :must, :may, :not
    end

    class DITStructureRule < AbstractDefinition
      # Has a ruleid, not an oid!
      attr_ldap_qdescrs    :name
      attr_ldap_qdstring   :desc
      attr_ldap_boolean    :obsolete
      attr_ldap_oid        :form # mandatory
      attr_ldap_oids       :sup # attr_ldap_ruleids
    end

    class NameForm < NameDescObsoleteDefiniton
      attr_ldap_oid        :oc # mandatory
      attr_ldap_oids       :must # mandatory
      attr_ldap_oids       :may
    end

  end
end

require 'ldaptic/syntaxes'
require 'ldaptic/matching_rules'

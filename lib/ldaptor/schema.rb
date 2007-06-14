module Ldaptor
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
      def attributes
        @attributes
      end

      def inspect
        "#<#{self.class} #{@oid} #{attributes.inspect}>"
      end

      def to_s
        @string
      end

      def initialize(string)
        @string = string.dup
        string = @string.dup
        # raise string unless string =~ /^\(\s*(\d[.\d]*\d) (.*?)\s*\)\s*$/
        @oid = extract_oid(string)
        array = build_array(string.dup)
        hash = array_to_hash(array)
        @attributes = hash
      end

      private

      def extract_oid(string)
        string.gsub!(/^\s*\(\s*(\d[\d.]*\d)\s*(.*?)\s*\)\s*$/,'\\2')
        $1
      end

      def build_array(string)
        array = []
        until string.empty?
          if string =~ /\A(\(\s*)?'/
            array << eatstr(string)
          elsif string =~ /\A[A-Z-]+[A-Z]\b/
            array << eat(string,/\A[A-Z0-9-]+/).downcase.gsub('-','_').to_sym
          elsif string =~ /\A(\(\s*)?[\w-]/
            array << eatary(string)
          else
            raise ParseError, "failed to parse schema entry #{@string.inspect}", caller[1..-1]
          end
        end
        array
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

      def eat(string,regex)
        string.gsub!(regex,'')
        string.strip!
        $1 || $&
      end

      def eatstr(string)
        if eaten = eat(string, /^\(\s*'([^)]+)'\s*\)/i)
          eaten.split("' '").collect{|attr| attr.strip }
        else
          eat(string,/^'([^']*)'\s*/)
        end
      end

      def eatary(string)
        if eaten = eat(string, /^\(([\w\d_\s\$-]+)\)/i)
          eaten.split("$").collect{|attr| attr.strip}
        else
          eat(string,/^([\w\d_-]+)/i)
        end
      end

      def method_missing(key,*args,&block)
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
          super(key,*args,&block)
        end
      end

    end

    class NameDescObsoleteDefiniton < AbstractDefinition
      attr_ldap_qdescrs    :name
      attr_ldap_qdstring   :desc
      attr_ldap_boolean    :obsolete
      def names
        Array(name)
      end
    end

    class ObjectClass < NameDescObsoleteDefiniton
      attr_ldap_oids       :sup
      attr_ldap_boolean    :structural, :auxiliary, :abstract
      attr_ldap_oids       :must, :may
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

      def syntax_oid
        @attributes[:syntax][/[0-9.]+/]
      end
      def syntax_len
        @attributes[:syntax][/\{.*\}/,1]
      end
      def syntax_name
        Ldaptor::SYNTAXES[syntax_oid].name
      end
      def syntax_object
        Ldaptor::SYNTAXES[syntax_oid]
        # Ldaptor::Syntaxes.const_get(syntax_name.delete(' ')) rescue Ldaptor::Syntaxes::DirectoryString
      end
      alias syntax syntax_object
    end

    class MatchingRule < NameDescObsoleteDefiniton
      attr_ldap_numericoid :syntax # mandatory
    end

    class MatchingRuleUse < NameDescObsoleteDefiniton
      attr_ldap_oids       :applies # mandatory
    end

    class LdapSyntax < AbstractDefinition
      # No name or obsolete flag
      attr_ldap_qdstring   :desc
      def parse(value)
        object.parse(value)
      end
      def format(value)
        object.format(value)
      end
      def object
        require 'ldaptor/syntaxes'
        Ldaptor::Syntaxes.for(desc.delete(" "))
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

module Ldaptor
  class SchemaLine # What is the "proper" name for a line of this format?

    def self.attr_boolean_schema(*attrs)
      attr_ldap_reader(*attrs)
      @hash ||= {}
      attrs.each do |attr|
        @hash[attr.to_s.upcase.to_s.gsub('_','-')] = :boolean
      end
    end

    def self.attr_string_schema(*attrs)
      attr_ldap_reader(*attrs)
      @hash ||= {}
      attrs.each do |attr|
        @hash[attr.to_s.upcase.to_s.gsub('_','-')] = :string
      end
    end

    def self.attr_array_schema(*attrs)
      attr_ldap_reader(*attrs)
      @hash ||= {}
      attrs.each do |attr|
        @hash[attr.to_s.upcase.to_s.gsub('_','-')] = :array
      end
    end

    def self.attr_ldap_reader(*attrs)
      attrs.each do |attr|
        class_eval(<<-EOS)
          def #{attr.to_s.downcase.gsub('-','_')}
            @hash[#{attr.to_s.upcase.gsub('_','-').inspect}]
          end
        EOS
      end
    end

    attr_accessor :oid
    def self.attributes
      @hash ||= {}
    end

    def initialize(string)
      @string = string.dup
      string = @string.dup
      # raise string unless string =~ /^\(\s*(\d[.\d]*\d) (.*?)\s*\)\s*$/
      string.gsub!(/^\s*\(\s*(\d[\d.]*\d)\s*(.*?)\s*\)\s*$/,'\\2')
      @oid = $1
      @hash = {}
      while value = eat(string,/^\s*([A-Z-]+)\s*/)
        if self.class.attributes[value] == :string
          @hash[value] = eatstr(string)
        elsif self.class.attributes[value] == :array
          @hash[value] = eatary(string)
        elsif self.class.attributes[value] == :boolean
          @hash[value] = true
        elsif value =~ /^X-/
          eatstr(string)
        end
      end
    end

    def to_s
      name
    end

    def eat(string,regex)
      string.gsub!(regex,'')
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

  end

  class AttributeType < SchemaLine
    attr_boolean_schema :obsolete, :single_value, :collective, :no_user_modification
    attr_string_schema  :name, :desc, :sup, :equality, :ordering, :substr, :syntax, :usage
  end

  class ObjectClass < SchemaLine
    attr_boolean_schema :structural, :auxiliary, :abstract, :obsolete
    attr_string_schema  :name, :desc
    attr_array_schema   :sup, :may, :must
  end
end

require 'ldap/schema'

module LDAP

  class Schema
    def aux(oc)
      self["dITContentRules"].to_a.each do |s|
        if s =~ /NAME\s+'#{oc}'/
          case s
          when /AUX\s+\(([\w\d_\s\$-]+)\)/i
            return $1.split("$").collect{|attr| attr.strip}
          when /AUX\s+([\w\d_-]+)/i
            return $1.split("$").collect{|attr| attr.strip}
          end
        end
      end
      return nil
    end
  end

end


require 'ldapter/schema'
require 'ldapter/errors'

module Ldapter

  # RFC2252.  Second column is "Human Readable"
  syntax_string = <<-EOF
ACI Item                        N  1.3.6.1.4.1.1466.115.121.1.1
Access Point                    Y  1.3.6.1.4.1.1466.115.121.1.2
Attribute Type Description      Y  1.3.6.1.4.1.1466.115.121.1.3
Audio                           N  1.3.6.1.4.1.1466.115.121.1.4
Binary                          N  1.3.6.1.4.1.1466.115.121.1.5
Bit String                      Y  1.3.6.1.4.1.1466.115.121.1.6
Boolean                         Y  1.3.6.1.4.1.1466.115.121.1.7
Certificate                     N  1.3.6.1.4.1.1466.115.121.1.8
Certificate List                N  1.3.6.1.4.1.1466.115.121.1.9
Certificate Pair                N  1.3.6.1.4.1.1466.115.121.1.10
Country String                  Y  1.3.6.1.4.1.1466.115.121.1.11
DN                              Y  1.3.6.1.4.1.1466.115.121.1.12
Data Quality Syntax             Y  1.3.6.1.4.1.1466.115.121.1.13
Delivery Method                 Y  1.3.6.1.4.1.1466.115.121.1.14
Directory String                Y  1.3.6.1.4.1.1466.115.121.1.15
DIT Content Rule Description    Y  1.3.6.1.4.1.1466.115.121.1.16
DIT Structure Rule Description  Y  1.3.6.1.4.1.1466.115.121.1.17
DL Submit Permission            Y  1.3.6.1.4.1.1466.115.121.1.18
DSA Quality Syntax              Y  1.3.6.1.4.1.1466.115.121.1.19
DSE Type                        Y  1.3.6.1.4.1.1466.115.121.1.20
Enhanced Guide                  Y  1.3.6.1.4.1.1466.115.121.1.21
Facsimile Telephone Number      Y  1.3.6.1.4.1.1466.115.121.1.22
Fax                             N  1.3.6.1.4.1.1466.115.121.1.23
Generalized Time                Y  1.3.6.1.4.1.1466.115.121.1.24
Guide                           Y  1.3.6.1.4.1.1466.115.121.1.25
IA5 String                      Y  1.3.6.1.4.1.1466.115.121.1.26
INTEGER                         Y  1.3.6.1.4.1.1466.115.121.1.27
JPEG                            N  1.3.6.1.4.1.1466.115.121.1.28
LDAP Syntax Description         Y  1.3.6.1.4.1.1466.115.121.1.54
LDAP Schema Definition          Y  1.3.6.1.4.1.1466.115.121.1.56
LDAP Schema Description         Y  1.3.6.1.4.1.1466.115.121.1.57
Master And Shadow Access Points Y  1.3.6.1.4.1.1466.115.121.1.29
Matching Rule Description       Y  1.3.6.1.4.1.1466.115.121.1.30
Matching Rule Use Description   Y  1.3.6.1.4.1.1466.115.121.1.31
Mail Preference                 Y  1.3.6.1.4.1.1466.115.121.1.32
MHS OR Address                  Y  1.3.6.1.4.1.1466.115.121.1.33
Modify Rights                   Y  1.3.6.1.4.1.1466.115.121.1.55
Name And Optional UID           Y  1.3.6.1.4.1.1466.115.121.1.34
Name Form Description           Y  1.3.6.1.4.1.1466.115.121.1.35
Numeric String                  Y  1.3.6.1.4.1.1466.115.121.1.36
Object Class Description        Y  1.3.6.1.4.1.1466.115.121.1.37
Octet String                    Y  1.3.6.1.4.1.1466.115.121.1.40
OID                             Y  1.3.6.1.4.1.1466.115.121.1.38
Other Mailbox                   Y  1.3.6.1.4.1.1466.115.121.1.39
Postal Address                  Y  1.3.6.1.4.1.1466.115.121.1.41
Protocol Information            Y  1.3.6.1.4.1.1466.115.121.1.42
Presentation Address            Y  1.3.6.1.4.1.1466.115.121.1.43
Printable String                Y  1.3.6.1.4.1.1466.115.121.1.44
Substring Assertion             Y  1.3.6.1.4.1.1466.115.121.1.58
Subtree Specification           Y  1.3.6.1.4.1.1466.115.121.1.45
Supplier Information            Y  1.3.6.1.4.1.1466.115.121.1.46
Supplier Or Consumer            Y  1.3.6.1.4.1.1466.115.121.1.47
Supplier And Consumer           Y  1.3.6.1.4.1.1466.115.121.1.48
Supported Algorithm             N  1.3.6.1.4.1.1466.115.121.1.49
Telephone Number                Y  1.3.6.1.4.1.1466.115.121.1.50
Teletex Terminal Identifier     Y  1.3.6.1.4.1.1466.115.121.1.51
Telex Number                    Y  1.3.6.1.4.1.1466.115.121.1.52
UTC Time                        Y  1.3.6.1.4.1.1466.115.121.1.53
EOF

  SYNTAXES = {} unless defined? SYNTAXES
  syntax_string.each_line do |line|
    d, h, oid = line.chomp.match(/(.*?)\s+([YN])  (.*)/).to_a[1..-1]
    hash = {:desc => d}
    if h == "N"
      hash[:x_not_human_readable] = "TRUE"
    end
    syntax = Ldapter::Schema::LdapSyntax.allocate
    syntax.instance_variable_set(:@oid, oid)
    syntax.instance_variable_set(:@attributes, hash)
    SYNTAXES[oid] = syntax
  end

  # The classes nestled here are responsible for casting attributes to and from
  # the appropriate type.  End users generally need not interact with these
  # directly.
  module Syntaxes
    # Returns the class for a given syntax name.  Falls back to
    # DirectoryString if there is not a more specific handler.
    #   Ldapter::Syntaxes.for("Generalized Time")
    #   #=> Ldapter::Syntaxes::GeneralizedTime
    def self.for(string)
      string = string.delete(' ')
      if const_defined?(string)
        const_get(string)
      else
        DirectoryString
      end
    end

    class Abstract
      # The +object+ argument refers back to the LDAP entry from which the
      # attribute in question came.  This is currently used only for the DN
      # syntax, to allow <tt>dn.find</tt> to work.
      def initialize(object = nil)
        @object = object
      end

      # RFC2522 Allows single but not double quotes, and slapd implements the
      # opposite of that. We'll allow both for now.
      PRINTABLE = "A-Za-z0-9'\"()+,./:? =-"
      def printable?(string)
        string =~ /\A[#{PRINTABLE}]+\z/
      end

      def format(value)
        if value.respond_to?(:utc)
          value.utc.strftime("%Y%m%d%H%M%S") + ".%06dZ" % [value.usec/100_000]
        elsif value == true
          'TRUE'
        elsif value == false
          'FALSE'
        elsif value.respond_to?(:dn)
          value.dn.to_s
        else
          value.to_s
        end
      end

      def error(value)
      end

      def self.format(object)
        new.format(object)
      end

      def self.parse(string)
        new.parse(string)
      end

    end

    class BitString < Abstract
      def error(string)
        "is invalid" unless string =~ /\A'[01]*'B\z/
      end
    end

    class Boolean < Abstract

      def parse(string)
        string == "TRUE"
      end

      def error(string)
        "must be a boolean" unless %w(TRUE FALSE).include?(string)
      end

    end

    class DirectoryString < Abstract

      def parse(string)
        string
      end

      def error(string)
        "can't be blank" if string.empty?
      end

    end

    class DN < Abstract

      def parse(string)
        ::Ldapter::DN(string, @object).freeze
      end

    end

    # LDAP timestamps look like <tt>YYYYmmddHHMMSS.uuuuuuZ</tt>.
    class GeneralizedTime < Abstract

      PATTERN = /\A\d{14}(?:\.\d{1,6})?Z\z/

      def parse(string)
        require 'time'
        parseable = string.sub(/(\.\d+)?(\w)$/, '\\2')
        Time.parse(parseable) + $1.to_f
      rescue ArgumentError
        begin
          require 'date'
          DateTime.parse(parseable) + $1.to_f
        rescue ArgumentError
          Time.now
        end
      end

      def error(string)
        'must be a time' unless string =~ PATTERN
      end

      def format(value)
        require 'time'
        if value.respond_to?(:to_str) && value !~ PATTERN && !Date._parse(value).empty?
          super(Time.parse(value))
        else
          super
        end
      end

    end

    class IA5String < Abstract
      PATTERN = /\A[\x00-\x7f]*\z/

      def parse(string)
        string
      end

      def error(string)
        'contains invalid characters' unless string =~ PATTERN
      end

    end

    class OtherMailbox < IA5String
    end

    class INTEGER < Abstract

      def parse(string)
        string.to_i
      end

      def error(string)
        "must be an integer" unless string =~ /\A\d+\z/
      end

    end

    class LDAPSyntaxDescription < Abstract

      def parse(string)
        Ldapter::Schema::LdapSyntax.new(string)
      end

    end

    class PrintableString < Abstract

      def parse(string)
        string
      end

      def error(string)
        return "can't be blank" if string.empty?
        'contains invalid characters' unless printable?(string)
      end
    end

    class CountryString < PrintableString
      def error(string)
        'must be two letters' unless printable?(string) && string =~ /\A..\z/
      end
    end

    class DeliveryMethod < PrintableString
      VALUES = %w(any mhs physical telex teletex g3fax g4fax ia5 videotex telephone)
      def error(string)
        'is invalid' unless VALUES.include?(string)
      end
    end

    class TelephoneNumber < PrintableString
    end

    class FacsimileTelephoneNumber < TelephoneNumber
      def error(string)
        return "can't be blank" if string.empty?
        unless string =~ /\A[#{PRINTABLE}][$#{PRINTABLE}]*\z/
          'contains invalid characters'
        end
      end
    end

    class TelexNumber < FacsimileTelephoneNumber
    end

    %w(ObjectClass AttributeType MatchingRule MatchingRuleUse DITContentRule DITStructureRule NameForm).each do |syntax|
      class_eval(<<-EOS, __FILE__, __LINE__.succ)
        class #{syntax}Description < Abstract
          def parse(string)
            Ldapter::Schema::#{syntax}.new(string)
          end
        end
      EOS
    end

  end

  # Microsoft junk.
  {
    "1.2.840.113556.1.4.906" => "1.3.6.1.4.1.1466.115.121.1.27",
    "1.2.840.113556.1.4.907" => "1.3.6.1.4.1.1466.115.121.1.5"
  }.each do |k, v|
    SYNTAXES[k] = SYNTAXES[v]
  end

end



require 'ldaptic/syntaxes'

module Ldaptic
  # RFC4517 - Lightweight Directory Access Protocol (LDAP): Syntaxes and Matching Rules
  # RFC4518 - Lightweight Directory Access Protocol (LDAP): Internationalized
  # String Preparation
  module MatchingRules
    def self.for(name)
      name = name.to_s
      name = name[0..0].upcase + name[1..-1].to_s
      if !name.empty? && const_defined?(name)
        const_get(name)
      else
        CaseIgnoreMatch
      end
    end

    class OctetStringMatch
      def matchable(value)
        value
      end

      def match(one, two)
        matchable(one) == matchable(two)
      end
    end

    class Boolean < OctetStringMatch
    end

    class CaseExactMatch < OctetStringMatch
      def matchable(value)
        super.gsub(/ +/, '  ').sub(/\A */, ' ').sub(/ *\z/, ' ')
      end
    end

    class CaseExactIA5Match < CaseExactMatch
    end

    class CaseIgnoreMatch < CaseExactMatch
      def matchable(value)
        super.downcase
      end
    end

    class CaseIgnoreIA5Match < CaseIgnoreMatch
    end

    class CaseIgnoreListMatch < CaseIgnoreMatch
    end

    class GeneralizedTimeMatch < OctetStringMatch
      def matchable(value)
        Ldaptic::Syntaxes::GeneralizedTime.parse(value)
      end
    end

    class NumericStringMatch < OctetStringMatch
      def matchable(value)
        super.delete(' ')
      end
    end

    class DistinguishedNameMatch < OctetStringMatch
      def matchable(value)
        Ldaptic::DN(value)
      end
    end

    class TelephoneNumberMatch < CaseIgnoreMatch
      # Doesn't remove unicode hyphen equivalents \u058A, \u2010, \u2011,
      # \u2212, \ufe63, or \uff0d on account of unicode being so darn difficult
      # to get right in both 1.8 and 1.9.
      def matchable(value)
        super.delete(' ').delete('-')
      end
    end

  end
end

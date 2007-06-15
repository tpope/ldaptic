$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldaptor/adapters'

class Ldaptor::Adapters::MockAdapter < Ldaptor::Adapters::AbstractAdapter
  def initialize
  end

  def schema(arg = nil)
    {
      'objectClasses' => [
        "( 2.5.6.0 NAME 'top' ABSTRACT MUST (objectClass) MAY (cn $ description $ distinguishedName ) )",
        "( 2.5.6.6 NAME 'person' SUP top STRUCTURAL MUST (cn) MAY (sn) )",
        "( 0.9.2342.19200300.100.4.19 NAME 'simpleSecurityObject' SUP top AUXILIARY MAY userPassword )",
        "( 9.9.9.1 NAME 'searchResult' SUP top STRUCTURAL MUST (filter $ scope) )"
      ],
      'attributeTypes' => [
        "( 2.5.4.0 NAME 'objectClass' SYNTAX '1.3.6.1.4.1.1466.115.121.1.38' NO-USER-MODIFICATION )",
        "( 2.5.4.3 NAME 'cn' SYNTAX '1.3.6.1.4.1.1466.115.121.1.15' SINGLE-VALUE )",
        "( 2.5.4.49 NAME 'distinguishedName' SYNTAX '1.3.6.1.4.1.1466.115.121.1.12' SINGLE-VALUE NO-USER-MODIFICATION )",
        "( 2.5.4.13 NAME 'description' SYNTAX '1.3.6.1.4.1.1466.115.121.1.15' )",
        "( 2.5.4.4 NAME 'sn' SYNTAX '1.3.6.1.4.1.1466.115.121.1.15' SINGLE-VALUE )",
        "( 2.5.4.35 NAME 'userPassword' SYNTAX '1.3.6.1.4.1.1466.115.121.1.40' )",
        "( 2.5.4.4 NAME 'filter' SYNTAX '1.3.6.1.4.1.1466.115.121.1.15' SINGLE-VALUE )",
        "( 9.9.9.2 NAME 'scope' SYNTAX '1.3.6.1.4.1.1466.115.121.1.27' SINGLE-VALUE )"
      ],
      "dITContentRules" => [
        "( 2.5.6.6 NAME 'person' AUX simpleSecurityObject )"
      ]
    }
  end

  def server_default_base_dn
    "DC=org"
  end

  # Returns a mock object which encapsulates the search query.
  def search(options)
    options = search_options(options)
    yield({
      'objectClass' => %w(top searchResult),
      'filter' => [options[:filter].to_s],
      'scope' => [options[:scope].to_s],
      'dn' => [options[:base]]
    })
  end
end

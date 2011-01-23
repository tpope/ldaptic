require File.join(File.dirname(File.expand_path(__FILE__)),'test_helper')
require 'ldapter'

class LdapterEntryTest < Test::Unit::TestCase

  class Entry < Ldapter::Entry
    def self.namespace
      Namespace.new
    end
  end

  class Namespace
    def attribute_type(attr)
    end
  end

  def test_human_attribute_name
    assert_equal 'Given name', Entry.human_attribute_name(:givenName)
    assert_equal 'User PKCS12', Entry.human_attribute_name(:userPKCS12)
  end

end

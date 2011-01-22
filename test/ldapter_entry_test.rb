require File.join(File.dirname(File.expand_path(__FILE__)),'test_helper')
require 'ldapter'

class LdapterEntryTest < Test::Unit::TestCase

  def test_human_attribute_name
    assert_equal 'Given name', Ldapter::Entry.human_attribute_name(:givenName)
  end

end

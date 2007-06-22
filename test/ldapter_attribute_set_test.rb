$:.unshift(File.join(File.dirname(__FILE__),'..','lib')).uniq!
require 'ldapter'
require File.join(File.dirname(__FILE__),"/mock_adapter")
require 'test/unit'

class LdapterAttributeSetTest < Test::Unit::TestCase
  class Mock < Ldapter::Namespace(:adapter => :mock)
  end

  def test_modify_description
    person = Mock::Person.new(:dn => "CN=Matz,DC=org")
    assert_equal [], person.description
    assert_nothing_raised { person.description.add("Foo") }
    assert_equal ["Foo"], person.description
    person.description.map! { |x| x.downcase }
    person.description << "bar"
    assert_equal ["foo","bar"], person.description
    person.description.unshift([["baz"]])
    assert_equal ["baz","foo","bar"], person.description
    assert_equal "foo", person.description.delete("FOO")
    assert_equal [nil], person.description.delete(["foo"])
    person.description.clear
    assert_equal [], person.description
  end

end

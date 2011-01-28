require File.join(File.dirname(File.expand_path(__FILE__)),'test_helper')
require 'ldaptic'
require File.join(File.dirname(File.expand_path(__FILE__)),'/mock_adapter')

class LdapticAttributeSetTest < Test::Unit::TestCase
  class Mock < Ldaptic::Class(:adapter => :mock)
  end

  def setup
    @person = Mock::Person.new(:dn => "CN=Matz,DC=org", :description => "Foo")
    @description = @person.description
  end

  def test_should_replace_description
    assert_same @description, @description.replace("bar", "baz")
    assert_equal ["bar", "baz"], @description
  end

  def test_should_add_to_description
    assert_same @description, @description.add("bar")
    assert_equal %w(Foo bar), @description
    assert_same @description, @description << "baz"
    assert_equal %w(Foo bar baz), @description
  end

  def test_should_delete_from_description
    assert_equal "Foo", @description.delete("fOO")
    assert_same @description, @description.delete("a", "b", "c")
  end

  def test_should_act_like_array
    assert_equal ["Foo"], @description
    @description.map! { |x| x.downcase }
    assert_same @description, @description.concat(["bar"])
    assert_equal ["foo", "bar"], @description
    assert_same @description, @description.unshift([["baz"]])
    assert_equal ["baz", "foo", "bar"], @description
    assert_equal 1, @description.index('foo')
    assert_equal "foo", @description.delete("foo")
    assert_nil   @description.delete("foo")
    @description.clear
    assert_equal [], @description
  end

  def test_should_join_on_to_s
    @description.replace("foo", "bar")
    assert_equal "foo\nbar", @description.to_s
  end

  def test_should_add_angles_on_inspect
    assert_equal '<["Foo"]>', @description.inspect
  end

  def test_should_humanize
    assert_equal 'Description', @description.human_name
  end

end

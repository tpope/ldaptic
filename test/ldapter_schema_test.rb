require File.join(File.dirname(__FILE__),'test_helper')
require 'ldapter/schema'

class LdapterSyntaxesTest < Test::Unit::TestCase
  NAME_FORM = "(1.2.3 NAME 'foo' DESC ('bar') OC objectClass MUST (cn $ ou) X-AWESOME TRUE)"
  ATTRIBUTE_TYPE = "(1.3.5 NAME 'cn' SYNTAX '1.3.6.1.4.1.1466.115.121.1.15{256}')"
  def assert_parse_error(&block)
    assert_raise(Ldapter::Schema::ParseError,&block)
  end

  def test_name_form
    name_form = Ldapter::Schema::NameForm.new(NAME_FORM)
    assert_equal "1.2.3", name_form.oid
    assert_equal "foo", name_form.name
    assert_equal %w(foo), name_form.names
    assert_equal %w(cn ou), name_form.must
    assert name_form.x_awesome?
    assert !name_form.x_lame
    assert_raise(NoMethodError) { name_form.applies }
    assert_raise(ArgumentError) { name_form.desc(1) }
    assert_raise(ArgumentError) { name_form.x_lame(1) }
    assert_equal nil, name_form.may
    assert_equal NAME_FORM, name_form.to_s
    assert name_form.inspect.include?("#<Ldapter::Schema::NameForm 1.2.3 {")
  end

  def test_object_class
    assert_equal "AUXILIARY", Ldapter::Schema::ObjectClass.new("(1.2 AUXILIARY)").kind
  end

  def test_attribute_type
    attribute_type = Ldapter::Schema::AttributeType.new(ATTRIBUTE_TYPE)
    assert_equal 256, attribute_type.syntax_len
    assert_not_nil attribute_type.syntax
  end

  def test_parse_error
    assert_parse_error { Ldapter::Schema::NameForm.new("x") }
    assert_parse_error { Ldapter::Schema::NameForm.new("(1.2.3 NAME (foo | bar))") }
    assert_parse_error { Ldapter::Schema::NameForm.new("(1.2.3 &)") }
  end

end

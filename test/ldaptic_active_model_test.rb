require File.join(File.dirname(File.expand_path(__FILE__)),'test_helper')
require 'ldaptic'
require File.join(File.dirname(File.expand_path(__FILE__)),'/mock_adapter')
require 'active_model'

class LdapticActiveModelTest < Test::Unit::TestCase
  include ActiveModel::Lint::Tests

  class Mock < Ldaptic::Class(:adapter => :mock)
  end

  def setup
    @model = Mock::Person.new
  end

  def test_changes
    @model.description = 'Bar'
    assert_equal ['Bar'], @model.changes['description']
  end

  def test_errors
    assert @model.invalid?
    assert_equal ['Common name is mandatory'], @model.errors.full_messages
    @model.cn = 'Douglas'
    @model.age = 'forty two'
    assert @model.invalid?
    assert_equal ['Age must be an integer'], @model.errors.full_messages
    @model.age = 42
    assert @model.valid?
    @model[:userPassword] = 'lol'
    assert @model.invalid?
    assert_equal ['User password is forbidden'], @model.errors.full_messages
  end

  def test_before_type_cast
    @model.description = ''
    assert_equal [], @model.description_before_type_cast
  end

end

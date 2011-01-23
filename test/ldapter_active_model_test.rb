require File.join(File.dirname(File.expand_path(__FILE__)),'test_helper')
require 'ldapter'
require File.join(File.dirname(File.expand_path(__FILE__)),'/mock_adapter')
require 'active_model'

class LdapterActiveModelTest < Test::Unit::TestCase
  include ActiveModel::Lint::Tests

  class Mock < Ldapter::Class(:adapter => :mock)
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
  end

end

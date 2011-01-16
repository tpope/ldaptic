require File.join(File.dirname(File.expand_path(__FILE__)),'test_helper')
require 'ldapter'
require File.join(File.dirname(File.expand_path(__FILE__)),'/mock_adapter')
require 'active_model'

class LdapterActiveModelTest < Test::Unit::TestCase
  include ActiveModel::Lint::Tests

  class Mock < Ldapter::Class(:adapter => :mock)
    class Top
      include ActiveModel::Validations
    end
  end

  def setup
    @model = Mock::Person.new
  end

  def test_changes
    @model.description = 'Bar'
    assert_equal ['Bar'], @model.changes['description']
  end

end

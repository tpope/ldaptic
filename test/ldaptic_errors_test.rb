require File.join(File.dirname(File.expand_path(__FILE__)),'test_helper')
require 'ldaptic/errors'

class LdapticErrorsTest < Test::Unit::TestCase

  NO_SUCH_OBJECT = 32

  def test_should_not_raise_on_zero
    assert_nothing_raised { Ldaptic::Errors.raise_unless_zero(0, "success") }
  end

  def test_should_raise_no_such_object
    assert_raise(Ldaptic::Errors::NoSuchObject) { Ldaptic::Errors.raise_unless_zero(32, "no such object") }
  end

  def test_should_have_proper_error
    exception = Ldaptic::Errors.raise_unless_zero(1, "some error") rescue $!
    assert_equal 1, exception.code
    assert_equal "some error", exception.message
    assert_match(/^#{Regexp.escape(__FILE__)}/, exception.backtrace.first)
  end

end

#!/usr/bin/env ruby

require 'ldaptic/dn'
require 'ldaptic/filter'
require 'ldaptic/errors'
require 'ldaptic/schema'
require 'ldaptic/syntaxes'
require 'ldaptic/adapters'
require 'ldaptic/entry'
require 'ldaptic/methods'

# = Getting started
#
# See the methods of the Ldaptic module (below) for information on connecting.
#
# See the Ldaptic::Methods module for information on searching with your
# connection object.
#
# Search results are Ldaptic::Entry objects.  See the documentation for this
# class for information on manipulating and updating them, as well as creating
# new entries.
module Ldaptic

  SCOPES = {
    :base     => 0, # ::LDAP::LDAP_SCOPE_BASE,
    :onelevel => 1, # ::LDAP::LDAP_SCOPE_ONELEVEL,
    :subtree  => 2  # ::LDAP::LDAP_SCOPE_SUBTREE
  }

  # Default logger.  If none given, creates a new logger on $stderr.
  def self.logger
    unless @logger
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        return Rails.logger
      else
        require 'logger'
        @logger = Logger.new($stderr)
        @logger.level = Logger::WARN
      end
    end
    @logger
  end

  def self.logger=(logger)
    @logger = logger
  end

  # Returns an object that can be assigned directly to a variable.  This allows
  # for an "anonymous" Ldaptic object.
  #   @my_company = Ldaptic::Object(options)
  #   @my_company::User.class_eval do
  #     alias login sAMAccountName
  #   end
  def self.Object(options={}, &block)
    base = ::Module.new do
      include Ldaptic::Module(options)
    end
    if block_given?
      base.class_eval(&block)
    end
    base
  end

  # Similar to Ldaptic::Class, accepting the same options.  Instead of
  # returning an anonymous class that activates upon inheritance, it returns an
  # anonymous module that activates upon inclusion.
  #   module MyCompany
  #     include Ldaptic::Module(options)
  #     # This class and many others are created automatically based on
  #     # information from the server.
  #     class User
  #       alias login sAMAccountName
  #     end
  #   end
  #
  #   me = MyCompany.search(:filter => {:cn => "Name, My"}).first
  #   puts me.login
  def self.Module(options={})
    Ldaptic::Module.new(options)
  end

  # The core constructor of Ldaptic.  This method returns an anonymous class
  # which can then be inherited from.
  #
  # The new class is not intended to be instantiated, instead serving as a
  # namespace. Included in this namespace is a set of class methods, as found
  # in Ldaptic::Methods, and a class hierarchy mirroring the object classes
  # found on the server.
  #
  #   options = {
  #     :adapter  => :active_directory,
  #     :host     => "pdc.mycompany.com",
  #     :username => "mylogin@mycompany.com",
  #     :password => "mypassword"
  #   }
  #
  #   class MyCompany < Ldaptic::Class(options)
  #     # This class and many others are created automatically based on
  #     # information from the server.
  #     class User
  #       alias login sAMAccountName
  #     end
  #   end
  #
  #   me = MyCompany.search(:filter => {:cn => "Name, My"}).first
  #   puts me.login
  #
  # Options given to this method are relayed to Ldaptic::Adapters.for.  The
  # documentation for this method should be consulted for further information.
  def self.Class(options={})
    klass = ::Class.new(Class)
    klass.instance_variable_set(:@options, Ldaptic::Adapters.for(options))
    klass
  end

  class << self
    alias Namespace Class
  end

  # An instance of this subclass of ::Module is returned by the Ldaptic::Module
  # method.
  class Module < ::Module #:nodoc:
    def initialize(options={})
      super()
      @options = options
    end
    def append_features(base)
      base.extend(Methods)
      base.instance_variable_set(:@adapter, Ldaptic::Adapters.for(@options))
      base.module_eval { build_hierarchy }
    end
  end

  # The anonymous class returned by the Ldaptic::Class method descends from
  # this class.
  class Class #:nodoc:
    class << self
      # Callback which triggers the magic.
      def inherited(subclass)
        if options = @options
          subclass.class_eval { include Ldaptic::Module.new(options) }
        else
          subclass.instance_variable_set(:@adapter, @adapter)
        end
        super
      end
      private :inherited, :new
    end
  end

end

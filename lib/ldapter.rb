#!/usr/bin/ruby

require 'ldapter/core_ext'
require 'ldap/dn'
require 'ldap/filter'
require 'ldapter/errors'
require 'ldapter/schema'
require 'ldapter/syntaxes'
require 'ldapter/adapters'
require 'ldapter/entry'
require 'ldapter/methods'

# = Getting started
#
# See the methods of the Ldapter module (below) for information on connecting.
#
# See the Ldapter::Methods module for information on searching with your
# connection object.
#
# Search results are Ldapter::Entry objects.  See the documentation for this
# class for information on manipulating and updating them, as well as creating
# new entries.
module Ldapter

  SCOPES = {
    :base     => 0, # ::LDAP::LDAP_SCOPE_BASE,
    :onelevel => 1, # ::LDAP::LDAP_SCOPE_ONELEVEL,
    :subtree  => 2  # ::LDAP::LDAP_SCOPE_SUBTREE
  }

  # Returns an object that can be assigned directly to a variable.  This allows
  # for an "anonymous" Ldapter object.
  #   @my_company = Ldapter::Object(options)
  #   @my_company::User.class_eval do
  #     alias login sAMAccountName
  #   end
  def self.Object(options,&block)
    base = ::Module.new do
      include Ldapter::Module(options)
    end
    if block_given?
      base.class_eval(&block)
    end
    base
  end

  # Similar to Ldapter::Class, accepting the same options.  Instead of
  # returning an anonymous class that activates upon inheritance, it returns an
  # anonymous module that activates upon inclusion.
  #   module MyCompany
  #     include Ldapter::Module(options)
  #     # This class and many others are created automatically based on
  #     # information from the server.
  #     class User
  #       alias login sAMAccountName
  #     end
  #   end
  #
  #   me = MyCompany.search(:filter => {:cn => "Name, My"}).first
  #   puts me.login
  def self.Module(options)
    Ldapter::Module.new(options)
  end

  # The core constructor of Ldapter.  This method returns an anonymous class
  # which can then be inherited from.
  #
  # The new class is not intended to be instantiated, instead serving as a
  # namespace. Included in this namespace is a set of class methods, as found
  # in Ldapter::Methods, and a class hierarchy mirroring the object classes
  # found on the server.
  #
  #   options = {
  #     :adapter  => :active_directory,
  #     :host     => "pdc.mycompany.com",
  #     :username => "mylogin@mycompany.com",
  #     :password => "mypassword"
  #   }
  #
  #   class MyCompany < Ldapter::Class(options)
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
  # Options given to this method are relayed to Ldapter::Adapters.for.  The
  # documentation for this method should be consulted for further information.
  def self.Class(options)
    klass = ::Class.new(Class)
    klass.instance_variable_set(:@options, Ldapter::Adapters.for(options))
    klass
  end

  class << self
    alias Namespace Class
  end

  # An instance of this subclass of ::Module is returned by the Ldapter::Module
  # method.
  class Module < ::Module #:nodoc:
    def initialize(options)
      super()
      @options = options
    end
    def append_features(base)
      base.extend(Methods)
      base.instance_variable_set(:@adapter, Ldapter::Adapters.for(@options))
      base.module_eval { build_hierarchy }
    end
  end

  # The anonymous class returned by the Ldapter::Class method descends from
  # this class.
  class Class #:nodoc:
    class << self
      # Callback which triggers the magic.
      def inherited(subclass)
        if options = @options
          subclass.class_eval { include Ldapter::Module.new(options) }
        else
          subclass.instance_variable_set(:@adapter, @adapter)
        end
        super
      end
      private :inherited, :new
    end
  end

end

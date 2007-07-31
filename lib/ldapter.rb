#!/usr/bin/ruby
# $Id$
# -*- ruby -*- vim:set ft=ruby et sw=2 sts=2:

require 'ldapter/core_ext'
require 'ldap/dn'
require 'ldap/filter'
require 'ldapter/errors'
require 'ldapter/schema'
require 'ldapter/syntaxes'
require 'ldapter/adapters'
require 'ldapter/entry'
require 'ldapter/methods'

module Ldapter

  SCOPES = {
    :base     => 0, # ::LDAP::LDAP_SCOPE_BASE,
    :onelevel => 1, # ::LDAP::LDAP_SCOPE_ONELEVEL,
    :subtree  => 2  # ::LDAP::LDAP_SCOPE_SUBTREE
  }

  # Returns an object that can be assigned directly to a constant.
  #   MyCompany = Ldapter::Object(options)
  def self.Object(options,&block)
    ::Module.new do
      include Ldapter::Module(options)
    end
  end

  # Returns a module that activates when included.
  #   module MyCompany
  #     include Ldapter::Module(options)
  #   end
  def self.Module(options)
    Ldapter::Module.new(options)
  end

  # The core constructor of Ldapter.  This method returns an anonymous class
  # which can then be inherited from.
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
  class Module < ::Module
    def initialize(options)
      super()
      @options = options
    end
    def append_features(base)
      base.extend(Methods)
      base.instance_variable_set(:@adapter, Ldapter::Adapters.for(@options))
      base.send(:build_hierarchy)
    end
  end

  # The anonymous class returned by the Ldapter::Class method descends from
  # this class.
  class Class
    class << self
      # Callback which triggers the magic.
      def inherited(subclass)
        if @options
          # subclass.extend(Methods)
          subclass.send(:include, Ldapter::Module.new(@options))
        else
          subclass.instance_variable_set(:@adapter, @adapter)
        end
        super
      end
      private :inherited, :new
    end
  end

end

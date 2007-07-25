module Ldapter
  # RFC1823 - The LDAP Application Program Interface
  module Adapters

    @adapters ||= {}

    def self.register(name, mod)
      @adapters[name.to_sym] = mod
      @adapters
    end

    def self.for(options)
      require 'ldapter/adapters/abstract_adapter'
      if defined?(::LDAP::Conn) && options.kind_of?(::LDAP::Conn)
        options = {:adapter => :ldap_conn, :connection => options}
      elsif defined?(::Net::LDAP) && options.kind_of?(::Net::LDAP)
        options = {:adapter => :net_ldap, :connection => options}
      end
      if options.kind_of?(Hash)
        options = options.inject({}) {|h,(k,v)| h[k.to_sym] = v; h}
        if options.has_key?(:connection) && !options.has_key?(:adapter)
          options[:adapter] = options[:connection].class.name.downcase.gsub('::','_')
        end
        options[:adapter] ||= default_adapter
        unless options[:adapter]
          Ldapter::Errors.raise(ArgumentError.new("No adapter specfied"))
        end
        begin
          require "ldapter/adapters/#{options[:adapter]}_adapter"
        rescue LoadError
        end
        if adapter = @adapters[options[:adapter].to_sym]
          adapter.new(options)
        else
          Ldapter::Errors.raise(ArgumentError.new("Adapter #{options[:adapter]} not found"))
        end
      else
        if options.kind_of?(::Ldapter::Adapters::AbstractAdapter)
          options
        else
          Ldapter::Errors.raise(TypeError.new("#{options.class} is not a valid connection type"))
        end
      end
    end

    def self.default_adapter
      require 'ldap'
      :ldap_conn
    rescue LoadError
      begin
        require 'net/ldap'
        :net_ldap
      rescue LoadError
      end
    end

  end
end

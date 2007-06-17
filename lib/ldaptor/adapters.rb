module Ldaptor
  module Adapters

    def self.register(name, mod)
      @adapters ||= {}
      @adapters[name.to_sym] = mod
      @adapters
    end

    def self.for(options)
      if defined?(::LDAP::Conn) && options.kind_of?(::LDAP::Conn)
        options = {:adapter => :ldap, :connection => options}
      elsif defined?(::Net::LDAP) && options.kind_of?(::Net::LDAP)
        options = {:adapter => :net_ldap, :connection => options}
      end
      if options.kind_of?(Hash)
        options = options.inject({}) {|h,(k,v)| h[k.to_sym] = v; h}
        raise Ldaptor::Error, "No adapter specfied", caller[1..-1] unless options[:adapter]
        begin
          require "ldaptor/adapters/#{options[:adapter]}_adapter"
        rescue LoadError
        end
        if adapter = @adapters[options[:adapter].to_sym]
          adapter.new(options)
        else
          raise Ldaptor::Error, "Adapter #{options[:adapter]} not found", caller[1..-1]
        end
      else
        require 'ldaptor/adapters/abstract_adapter'
        if options.kind_of?(::Ldaptor::Adapters::AbstractAdapter)
          options
        else
          raise TypeError, "#{options.class} is not a valid connection type", caller[1..-1]
        end
      end
    end

  end
end

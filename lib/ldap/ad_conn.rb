require 'ldap'

module LDAP
  # Convenience class which delegates reading operations to one class, and
  # writing operations to another.
  class DualConn < LDAP::Conn

    attr_accessor :reader, :writer

    # def initialize(read_conn, write_conn)
      # @reader = read_conn
      # @writer = write_conn
    # end

    # def self.read_with(*methods)
      # return
      # methods.each do |method|
        # class_eval "def #{method}(*args,&block) @reader.#{method}(*args,&block) end"
      # end
    # end

    def self.write_with(*methods)
      methods.each do |method|
        class_eval(<<-EOS,__FILE__,__LINE__)
        def #{method}(*args,&block)
          if @writer
            @writer.#{method}(*args,&block)
          else
            super
          end
        end
        EOS
      end
    end

    def self.both_with(*methods)
      methods.each do |method|
        class_eval(<<-EOS,__FILE__,__LINE__)
        def #{method}(*args,&block)
          if @writer
            @writer.#{method}(*args,&block)
          end
          super
          #[@reader,@writer].each {|c|c.#{method}(*args,&block)}; self
        end
        EOS
      end
    end

    # read_with :compare, :compare_ext, :err2string, :get_option, :result2error, :root_dse, :schema, :search, :search2, :search_ext, :search_ext2
    write_with :add, :add_ext, :delete, :delete_ext, :modify, :modrdn, :modify_ext
    both_with :bind, :set_option, :simple_bind, :unbind

    def bound?
      super && [@writer].compact.all? {|c|c.bound?}
    end

    def err
      err = err
      if err == 0
        @writer.err
      else
        err
      end
    end

  end

  # This class is like a LDAP::Conn which binds before each method call and
  # unbinds afterwords.  This is useful with servers that disconnect after an
  # idle period (like Active Directory).
  class AutoConn < Conn

    instance_methods.each do |method|
      undef_method(method) unless method.to_s =~ /^__.*__$/
    end

    def initialize(*args)
      if args.first.respond_to?(:search_ext2)
        @connection = args.first
      else
        @connection = LDAP::Conn.new(*args)
      end
      @bound_options = []
    end

    def bind(dn=nil, password=nil, method=LDAP::LDAP_AUTH_SIMPLE, &block)
      if block_given?
        @connection.bind(db, password, method, &block)
      else
        @connection.bind(dn, password, method) {}
        @dn, @password, @method = dn, password, method
        self
      end
    end

    def unbind
      @bound_options = []
      if @method
        @dn = @password = @method = nil
      else
        @connection.unbind
      end
    end

    def bound_with_autobind?
      @method ? true : @connection.bound?
    end

    def while_bound
      if @method && !@connection.bound?
        begin
          @connection.bind(@dn, @password, @method)
          @bound_options.each do |(option, data)|
            @connection.set_option(option,data)
          end
          yield
        ensure
          @controls = @connection.controls
          @err = @connection.err
          @connection.unbind
        end
      else
        yield
      end
    end
    protected :while_bound

    attr_reader :controls, :err

    def set_option(option, data)
      while_bound do
        @connection.set_option(option, data)
      end
      if bound_with_autobind?
        @bound_options.reject! {|(o,d)| o == option}
        @bound_options << [option, data]
      end
      self
    end

    def method_missing(method, *args, &block)
      while_bound do
        @connection.__send__(method, *args, &block)
      end
    end

  end

  # LDAP::AutoConn wrapped around a LDAP::DualConn which connects as a reader
  # to port 3268, and as a writer on port 389.  This in my experience is the
  # ideal setup for an Active Directory connection.
  class ADConn < AutoConn

    def initialize(host)
      @host = host
      connection = new_unbound_connection
      super(connection)
    end

    def new_unbound_connection
      connection = LDAP::DualConn.new(@host,3268)
      connection.writer = LDAP::Conn.new(@host,389)
      connection.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION,3)
      connection
    end

    def while_bound
      if !@connection.bound?
        @connection.send(:initialize, @host, 3268)
        @connection.writer.send(:initialize, @host, 389)
        @connection.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION,3)
      end
      super
    end

    # Check whether a set of credentials is valid.  Returns a boolean.
    def authenticate(dn, password, method=LDAP::LDAP_AUTH_SIMPLE)
      @connection.writer.bind(dn, password, method) {}
      true
    rescue
      false
    end

  end

end

def DateTime.microsoft(tinies)
  new(1601,1,1).new_offset(Time.now.utc_offset/60/60/24.0) + tinies/1e7/60/60/24
end

def Time.microsoft(tinies)
  dt = DateTime.microsoft(tinies)
  Time.local(dt.year,dt.mon,dt.day,dt.hour,dt.min,dt.sec,dt.sec_fraction*60*60*24*1e6)
end


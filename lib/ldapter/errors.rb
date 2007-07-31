module Ldapter

  class Error < ::RuntimeError #:nodoc:
  end

  # All server errors are instances of this class.  The error message and error
  # code can be accessed with <tt>exception.message</tt> and
  # <tt>exception.code</tt> respectively.
  class ServerError < Error
    attr_accessor :code
  end

  # The module houses all subclasses of Ldapter::ServerError.  The methods
  # contained within are for internal use only.
  module Errors

    #{
    #  0=>"Success",
    #  1=>"Operations error",
    #  2=>"Protocol error",
    #  3=>"Time limit exceeded",
    #  4=>"Size limit exceeded",
    #  5=>"Compare False",
    #  6=>"Compare True",
    #  7=>"Authentication method not supported"
    #  8=>"Strong(er) authentication required",
    #  9=>"Partial results and referral received",
    #  10=>"Referral",
    #  11=>"Administrative limit exceeded",
    #  12=>"Critical extension is unavailable",
    #  13=>"Confidentiality required",
    #  14=>"SASL bind in progress",
    #  16=>"No such attribute",
    #  17=>"Undefined attribute type",
    #  18=>"Inappropriate matching",
    #  19=>"Constraint violation",
    #  20=>"Type or value exists",
    #  21=>"Invalid syntax",
    #  32=>"No such object",
    #  33=>"Alias problem",
    #  34=>"Invalid DN syntax",
    #  35=>"Entry is a leaf",
    #  36=>"Alias dereferencing problem",
    #  47=>"Proxy Authorization Failure",
    #  48=>"Inappropriate authentication",
    #  49=>"Invalid credentials",
    #  50=>"Insufficient access",
    #  51=>"Server is busy",
    #  52=>"Server is unavailable",
    #  53=>"Server is unwilling to perform",
    #  54=>"Loop detected",
    #  64=>"Naming violation",
    #  65=>"Object class violation",
    #  66=>"Operation not allowed on non-leaf",
    #  67=>"Operation not allowed on RDN",
    #  68=>"Already exists",
    #  69=>"Cannot modify object class",
    #  70=>"Results too large",
    #  71=>"Operation affects multiple DSAs",
    #  80=>"Internal (implementation specific) error",
    #  81=>"Can't contact LDAP server",
    #  82=>"Local error",
    #  83=>"Encoding error",
    #  84=>"Decoding error",
    #  85=>"Timed out",
    #  86=>"Unknown authentication method",
    #  87=>"Bad search filter",
    #  88=>"User cancelled operation",
    #  89=>"Bad parameter to an ldap routine",
    #  90=>"Out of memory",
    #  91=>"Connect error",
    #  92=>"Not Supported",
    #  93=>"Control not found",
    #  94=>"No results returned",
    #  95=>"More results to return",
    #  96=>"Client Loop",
    #  97=>"Referral Limit Exceeded",
    #}

    # Error code 32.
    class NoSuchObject < ServerError
    end

    EXCEPTIONS = {
      32 => NoSuchObject
    }

    class << self

      # Provides a backtrace minus all files shipped with Ldapter.
      def application_backtrace
        dir = File.dirname(File.dirname(__FILE__))
        c = caller
        c.shift while c.first[0,dir.length] == dir
        c
      end

      # Raise an exception (object only, no strings or classes) with the
      # backtrace stripped of all Ldapter files.
      def raise(exception)
        exception.set_backtrace(application_backtrace)
        Kernel.raise exception
      end

      def for(code, message = nil) #:nodoc:
        message ||= "Unknown error #{code}"
        klass = EXCEPTIONS[code] || ServerError
        exception = klass.new(message)
        exception.code = code
        exception
      end

      # Given an error code and a message, raise an Ldapter::ServerError unless
      # the code is zero.  The right subclass is selected automatically if it
      # is available.
      def raise_unless_zero(code, message = nil)
        return if code.zero?
        raise self.for(code, message)
      end

    end

  end

end

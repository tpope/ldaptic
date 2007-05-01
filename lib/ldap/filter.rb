module LDAP

  # Escape a string for use in an LDAP filter.  If the second argument is
  # +false+, asterisks are not escaped.
  def self.escape(string, escape_asterisks = true)
    string = string.utc.strftime("%Y%m%d%H%M%S.0Z") if string.respond_to?(:utc)
    string.to_s.gsub(/[()#{escape_asterisks ? :* : nil}\\\0-\37,]/) {|l| "\\" + l[0].to_s(16) }
  end

  # If the argument is already a valid LDAP::Filter object, return it
  # untouched.  Otherwise, pass it to the appropriate constructer of the
  # appropriate subclass.
  def self.Filter(argument)
    case argument
    when Filter::Abstract then argument
    when [],nil then nil
    when Array  then Filter::Join.new(argument)
    when Hash   then Filter::Hash.new(argument)
    when String then Filter::String.new(argument)
    else raise TypeError, "Unknown LDAP Filter type", caller
    end
  end

  module Filter

    # The filter class from which all others derive.
    class Abstract

      # Combine two filters with a logical AND.
      def &(other)
        And.new(self,other)
      end

      # Combine two filters with a logical OR.
      def |(other)
        Or.new(self,other)
      end

      # Negate a filter.
      #
      #   ~LDAP::Filter("(a=1)").to_s # => "(!(a=1))"
      def ~
        Not.new(self)
      end

      # Generates the filter as a string.  Returns "" for empty filters.
      def to_s
        process.to_s
      end

      def inspect
        if string = process
          "#<LDAP::Filter #{string}>"
        else
          "#<LDAP::Filter invalid>"
        end
      end

    end

    # This class is used for raw LDAP queries.  Note that the outermost set of
    # parentheses *must* be used.
    #
    #   LDAP::Filter("a=1")   # Wrong
    #   LDAP::Filter("(a=1)") # Correct
    class String < Abstract

      def initialize(string) #:nodoc:
        @string = string
      end

      # Returns the original string
      def process
        @string
      end

    end

    # Used in the implementation of LDAP::Filter::And and LDAP::Filter::Or.
    # For internal use only.
    class Join < Abstract
      def initialize(operator, *args) #:nodoc:
        @array = [operator] + args.map {|arg| LDAP::Filter(arg)}
      end
      def process
        "(#{@array})" if @array.compact.size > 1
      end
    end

    class And < Join
      def initialize(*args)
        super(:&, *args)
      end
    end

    class Or < Join
      def initialize(*args)
        super(:|, *args)
      end
    end

    class Not < Abstract
      def initialize(object)
        @object = LDAP::Filter(object)
      end
      def process
        process = @object.process and "(!#{process})"
      end
    end

    # A hash is the most general and most useful type of filter builder.
    #
    #   LDAP::Filter(
    #     :givenName => "David",
    #     :sn! => "Thomas",
    #     :postalCode => (70000..80000)
    #   ).to_s # => "(&(givenName=David)(&(postalCode>=70000)(postalCode<=80000))(!(sn=Thomas)))"
    #
    # Including :* => true allows asterisks to pass through unaltered.
    # Otherwise, they are escaped.
    #
    #    LDAP::Filter(:givenName => "Dav*", :* => true).to_s # => "(givenName=Dav*)"
    class Hash < Abstract

      attr_accessor :escape_asterisks
      attr_reader   :hash
      # Call LDAP::Filter(hash) instead of instantiating this class directly.
      def initialize(hash)
        @hash = hash.dup
        @escape_asterisks = !@hash.delete(:*)
      end

      def process
        nostar = @escape_asterisks
        string = @hash.map {|k,v| [k.to_s,v]}.sort.map do |(k,v)|
          k = k.to_s.dup
          inverse = !!k.sub!(/!$/,'')
          if v.respond_to?(:to_ary)
            q = "(|" + v.map {|e| "(#{k}=#{LDAP.escape(e,nostar)})"}.join + ")"
          elsif v.kind_of?(Range)
            q = []
            if v.first != -1.0/0
              q << "(#{k}>=#{LDAP.escape(v.first,nostar)})"
            end
            if v.last != 1.0/0
              if v.exclude_end?
                q << "(!(#{k}>=#{LDAP.escape(v.last,nostar)}))"
              else
                q << "(#{k}<=#{LDAP.escape(v.last,nostar)})"
              end
            end
            q = "(&#{q})"
          elsif v == true
            q = "(#{k}=*)"
          elsif v == false
            q = "(!(#{k}=*))"
          else
            q = "(#{k}=#{LDAP.escape(v,nostar)})"
          end
          inverse ? "(!#{q})" : q
        end.join
        case @hash.size
        when 0 then nil
        when 1 then string
        else "(&#{string})"
        end
      end
    end

    module Conversions
      def to_ldap_filter
        LDAP::Filter(self)
      end
    end

    ::Hash.send(:include, Conversions)
    ::String.send(:include, Conversions)

  end

end


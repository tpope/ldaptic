require 'ldap/escape'

module LDAP #:nodoc:

  # If the argument is already a valid LDAP::Filter object, return it
  # untouched.  Otherwise, pass it to the appropriate constructer of the
  # appropriate subclass.
  #
  #   Ldapter::Filter("(cn=Wu*)").to_s        #=> '(cn=Wu*)'
  #   Ldapter::Filter({:cn=>"Wu*"}).to_s      #=> '(cn=Wu\2A)'
  #   Ldapter::Filter(["(cn=?*)","Wu*"]).to_s #=> '(cn=Wu\2A*)'
  def self.Filter(argument)
    case argument
    when Filter::Abstract then argument
    when [],nil then nil
    when Array  then Filter::Array    .new(argument)
    when Hash   then Filter::Hash     .new(argument)
    when String then Filter::String   .new(argument)
    when Symbol then Filter::Attribute.new(argument)
    when Proc, Method
      LDAP::Filter(if argument.arity > 0
        argument.call(Filter::Spawner)
      else
        Filter::Spawner.instance_eval(&argument)
      end)
    else raise TypeError, "Unknown LDAP Filter type", caller
    end
  end

  # See LDAP.Filter for the contructor and LDAP::Filter::Abstract for methods
  # common to all filters.
  #
  # Useful subclasses include String, Array, and Hash.
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

      # Generates the filter as a string.
      def to_s
        process || "(objectClass=*)"
      end

      alias to_str to_s

      def inspect
        if string = process
          "#<LDAP::Filter #{string}>"
        else
          "#<LDAP::Filter invalid>"
        end
      end

      def to_net_ldap_filter #:nodoc:
        Net::LDAP::Filter.construct(process)
      end

      def to_ber #:nodoc:
        to_net_ldap_filter.to_ber
      end

    end

    module Spawner # :nodoc:
      def self.method_missing(method)
        Attribute.new(method)
      end
    end

    class Attribute < Abstract
      def initialize(name)
        if name.kind_of?(Symbol)
          name = name.to_s.tr('_-','-_')
        end
        @name = name
      end
      %w(== =~ >= <=).each do |method|
        define_method(method) do |other|
          Pair.new(@name,other,method)
        end
      end
      def process
        "(#{@name}=*)"
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

    # Does ? parameter substitution.
    #
    #   LDAP::Filter(["(cn=?*)","Sm"]).to_s #=> "(cn=Sm*)"
    class Array < Abstract
      def initialize(array) #:nodoc:
        @template = array.first
        @parameters = array[1..-1]
      end
      def process
        parameters = @parameters.dup
        string = @template.gsub('?') { LDAP.escape(parameters.pop) }
      end
    end

    # Used in the implementation of LDAP::Filter::And and LDAP::Filter::Or.
    # For internal use only.
    class Join < Abstract
      def initialize(operator, *args) #:nodoc:
        @array = [operator] + args.map {|arg| LDAP::Filter(arg)}
      end
      def process
        "(#{@array*''})" if @array.compact.size > 1
      end
      def to_net_ldap_filter #:nodoc
        @array[1..-1].inject {|m,o| m.to_net_ldap_filter.send(@array.first,o.to_net_ldap_filter)}
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
      def to_net_ldap_filter #:nodoc:
        ~ @object.to_net_ldap_filter
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
        string = @hash.map {|k,v| [k.to_s,v]}.sort.map do |(k,v)|
          Pair.new(k,v,@escape_asterisks ? "==" : "=~").process
        end.join
        case @hash.size
        when 0 then nil
        when 1 then string
        else "(&#{string})"
        end
      end
    end

    # Internal class used to process a single entry from a hash.
    class Pair < Abstract
      INVERSE_OPERATORS = {
        "!=" => "==",
        "!~" => "=~",
        ">"  => "<=",
        "<"  => ">="
      }
      def initialize(key, value, operator)
        @key, @value, @operator = key.to_s.dup, value, operator.to_s
        @inverse = !!@key.sub!(/!$/,'')
        if op = INVERSE_OPERATORS[@operator]
          @inverse ^= true
          @operator = op
        end
      end

      def process
        k = @key
        v = @value
        if @operator == "=~"
          operator = "=="
          star = true
        else
          operator = @operator
          star = false
        end
        inverse = @inverse
        operator = "=" if operator == "=="
        if v.respond_to?(:to_ary)
          q = "(|" + v.map {|e| "(#{LDAP.escape(k)}=#{LDAP.escape(e,star)})"}.join + ")"
        elsif v.kind_of?(Range)
          q = []
          if v.first != -1.0/0
            q << "(#{LDAP.escape(k)}>=#{LDAP.escape(v.first,star)})"
          end
          if v.last != 1.0/0
            if v.exclude_end?
              q << "(!(#{LDAP.escape(k)}>=#{LDAP.escape(v.last,star)}))"
            else
              q << "(#{LDAP.escape(k)}<=#{LDAP.escape(v.last,star)})"
            end
          end
          q = "(&#{q*""})"
        elsif v == true || v == :*
          q = "(#{LDAP.escape(k)}=*)"
        elsif !v
          q = "(#{LDAP.escape(k)}=*)"
          inverse ^= true
        else
          q = "(#{LDAP.escape(k)}#{operator}#{LDAP.escape(v,star)})"
        end
        inverse ? "(!#{q})" : q
      end
    end

    module Conversions #:nodoc:
      def to_ldap_filter
        LDAP::Filter(self)
      end
    end

  end

end

class Hash
  include LDAP::Filter::Conversions
end
class String
  include LDAP::Filter::Conversions
end

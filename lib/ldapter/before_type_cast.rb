module Ldapter
  # Mixing in this module into an entry class causes special _before_type_cast
  # accessors to appear on instances.  Said accessors always return a string,
  # joining multiple elements with newlines.  This may prove useful in
  # conjunction with Rails.
  #
  # class L < Ldapter::Class(:adapter => :ldap_conn)
  #   class Top
  #     include Ldapter::BeforeTypeCast
  #   end
  # end
  module BeforeTypeCast

    def read_attribute_before_type_cast(attribute)
      read_attribute(attribute, true).before_type_cast.join("\n")
    end

    # If the attribute is human readable and allows multiple values, and a
    # string value is given for assignment, split said string upon newlines.
    # This reverses the effect of #read_attribute_before_type_cast.
    def write_attribute(attribute, value)
      syntax = namespace.attribute_syntax(attribute)
      # unless the syntax is not human readable
      unless syntax && syntax.x_not_human_readable?
        # Unless the attribute is a single value
        unless namespace.attribute_type(attribute).single_value?
          # Split on newlines to get multiple values
          value = value.to_str.split("\n") if value.respond_to?(:to_str)
        end
      end
      super(attribute, value)
    end

    def method_missing(method,*args,&block)
      if method.to_s =~/(.*)_before_type_cast$/
        read_attribute_before_type_cast($1.to_sym,*args,&block)
      else
        super(method,*args,&block)
      end
    end

  end
end

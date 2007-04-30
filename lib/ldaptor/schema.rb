require 'ldap/schema'

module LDAP

  class Schema
    def aux(oc)
      self["dITContentRules"].to_a.each do |s|
        if s =~ /NAME\s+'#{oc}'/
          case s
          when /AUX\s+\(([\w\d_\s\$-]+)\)/i
            return $1.split("$").collect{|attr| attr.strip}
          when /AUX\s+([\w\d_-]+)/i
            return $1.split("$").collect{|attr| attr.strip}
          end
        end
      end
      return nil
    end
  end

end


require 'net/ldap'
class Net::LDAP # :nodoc:

  # Erroneously descends from Exception
  remove_const(:LdapError)
  class LdapError < RuntimeError # :nodoc:
  end

  class Connection # :nodoc:
    # Monkey-patched in support for new superior.
    def rename args
      old_dn = args[:olddn] or raise "Unable to rename empty DN"
      new_rdn = args[:newrdn] or raise "Unable to rename to empty RDN"
      new_superior = args[:newsuperior]
      delete_attrs = args[:delete_attributes] ? true : false

      request = [old_dn.to_ber, new_rdn.to_ber, delete_attrs.to_ber]
      request << new_superior.to_ber(128) if new_superior
      request = request.to_ber_appsequence(12)
      pkt = [next_msgid.to_ber, request].to_ber_sequence
      @conn.write pkt

      (be = @conn.read_ber(AsnSyntax)) && (pdu = Net::LdapPdu.new( be )) && (pdu.app_tag == 13) or raise LdapError.new( "response missing or invalid" )
      pdu.result_code
    end
  end
end

warn "ldaptor is deprecated; use ldapter instead\n#{caller.join("\n")}"
require 'ldapter'
Ldaptor = Ldapter

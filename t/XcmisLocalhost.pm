# Tests using an alfresco installed on localhost
package XcmisLocalhost;

use CmisBase;
our @ISA = (CmisBase);

sub new {
  my $class = shift;

  return $class->SUPER::new({
    url => "http://localhost:9090/xcmis/rest/cmisatom",
    user => "root",
    password => "exo",
  });
}

1;

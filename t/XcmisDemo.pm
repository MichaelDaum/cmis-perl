# Tests using an alfresco installed on localhost
package XcmisDemo;

use CmisBase;
our @ISA = (CmisBase);

sub new {
  my $class = shift;

  return $class->SUPER::new({
    url => "http://xcmis.org/xcmis1/rest/cmisatom",
    user => "root",
    password => "exo",
  });
}

1;

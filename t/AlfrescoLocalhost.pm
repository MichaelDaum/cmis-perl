# Tests using an alfresco installed on localhost
package AlfrescoLocalhost;

use CmisBase;
our @ISA = (CmisBase);

sub new {
  my $class = shift;

  return $class->SUPER::new({
    url => "http://alfresco/alfresco/service/cmis",
    user => "admin",
    password => "admin",
  });
}

1;

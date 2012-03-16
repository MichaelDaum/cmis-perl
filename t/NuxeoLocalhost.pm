# Tests using an alfresco installed on localhost
package NuxeoLocalhost;

use CmisBase;
our @ISA = (CmisBase);

sub new {
  my $class = shift;

  return $class->SUPER::new({
    url => "http://localhost:8080/nuxeo/atom/cmis",
    user => "crawler",
    password => "crawler",
  });
}

1;

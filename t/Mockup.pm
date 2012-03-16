# Tests using an alfresco installed on localhost
package Mockup;

use CmisBase;
our @ISA = (CmisBase);

sub new {
  my $class = shift;

  return $class->SUPER::new({
     url => "http://foo.bar/cmis",
  });
}

1;


# Tests using an alfresco installed on localhost
package NuxeoDemoSite;

use CmisBase;
our @ISA = (CmisBase);

sub new {
  my $class = shift;

  return $class->SUPER::new({
    url => "http://cmis.demo.nuxeo.org/nuxeo/atom/cmis",
    user => "Administrator",
    password => "Administrator",
  });
}

1;

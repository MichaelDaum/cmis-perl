# Tests using a public test alfresco
package AlfrescoPreview;

use CmisBase;
our @ISA = (CmisBase);

sub new {
  my $class = shift;

  return $class->SUPER::new({
     url => "http://cmis.alfresco.com/service/cmis",
     user => "admin",
     password => "admin",
  });
}

1;

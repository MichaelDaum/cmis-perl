package CmisPluginSuite;
use Unit::TestSuite;
our @ISA = qw( Unit::TestSuite );

sub include_tests {
  qw( AlfrescoLocalhost );

  ###
  # AlfrescoDemoSite
  # AlfrescoLocalhost
  # NuxeoDemoSite
  # NuxeoLocalhost
  # XcmisLocalhost
  # Mockup
}

1;


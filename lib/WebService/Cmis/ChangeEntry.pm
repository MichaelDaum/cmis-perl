package WebService::Cmis::ChangeEntry;

=head1 NAME

WebService::Cmis::ChangeEntry

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

use strict;
use warnings;
use WebService::Cmis qw(:namespaces :relations);
use WebService::Cmis::AtomEntry ();
use Error qw(:try);

our @ISA = qw(WebService::Cmis::AtomEntry);

our $CMIS_XPATH_PROPERTIES = new XML::LibXML::XPathExpression('./*[local-name()="object" and namespace-uri()="'.CMISRA_NS.'"]/*[local-name()="properties" and namespace-uri()="'.CMIS_NS.'"]/*[@propertyDefinitionId]');
our $CMIS_XPATH_CHANGETYPE = new XML::LibXML::XPathExpression('./*[local-name()="object" and namespace-uri()="'.CMISRA_NS.'"]/*[local-name()="changeEventInfo" and namespace-uri()="'.CMIS_NS.'"]/*[local-name()="changeType" and namespace-uri()="'.CMIS_NS.'"]');
our $CMIS_XPATH_CHANGETIME = new XML::LibXML::XPathExpression('./*[local-name()="object" and namespace-uri()="'.CMISRA_NS.'"]/*[local-name()="changeEventInfo" and namespace-uri()="'.CMIS_NS.'"]/*[local-name()="changeTime" and namespace-uri()="'.CMIS_NS.'"]');
our $CMIS_XPATH_ACL = new XML::LibXML::XPathExpression('./*[local-name()="object" and namespace-uri()="'.CMISRA_NS.'"]/*[local-name()="acl" and namespace-uri()="'.CMIS_NS.'"]');

=head1 METHODS

=over 4

=cut

sub DESTROY {
  my $this = shift;

  undef $this->{xmlDoc};
  undef $this->{properties};
}

=item getProperties -> %properties

returns a hash of properties of the change entry. Note that depending on the
capabilities of the repository ("capabilityChanges") the list may not
include the actual property values that changed.

=cut

sub getProperties {
  my $this = shift;

  require WebService::Cmis::Property;
  unless (defined $this->{properties}) {
    foreach my $propNode ($this->{xmlDoc}->findnodes($CMIS_XPATH_PROPERTIES)) {
      my $property = WebService::Cmis::Property::load($propNode);
      #print STDERR "property = ".$property->toString."\n";
      $this->{properties}{$property->getId} = $property;
    }
  }

  return $this->{properties};
}

=item getProperty($propName) -> $propValue

returns the value of a given property or undef if not available.

This is not covered by the cmis specs but makes live easier.

=cut

sub getProperty {
  my ($this, $propName) = @_;

  my $props = $this->getProperties;
  return unless $props->{$propName};
  return $props->{$propName}->getValue;
}

=item getObjectId -> $objectId

returns the object ID of the object that changed.

=cut
sub getObjectId { 
  return $_[0]->getProperty('cmis:objectId');
}

=item getChangeTime -> $epochSeconds

returns epoch seconds representing the time the change occurred.

=cut

sub getChangeTime {
  my $this = shift;

  unless (defined $this->{changeTime}) {
    $this->{changeTime} = WebService::Cmis::Property::parseDateTime($this->{xmlDoc}->findvalue($CMIS_XPATH_CHANGETIME));
  }
  return $this->{changeTime};
}

=item getChangeType -> $changeType

returns the type of change that occurred. The resulting value must be
one of:

=over 4

=item created
=item updated
=item deleted
=item security

=back

=cut

sub getChangeType {
  my $this = shift;

  unless (defined $this->{changeType}) {
    require WebService::Cmis::Property;
    $this->{changeType} = $this->{xmlDoc}->findvalue($CMIS_XPATH_CHANGETYPE);
  }
  return $this->{changeType};
}

=item getACL -> $aclObject

returns the ACL object that is included with this Change Entry, or undef
if the change type is "deleted".

if you call getContentChanges with includeACL=true, you will get a ACL
information embedded in this ChangeEntry object. Change entries don't appear to
have a self URL so instead of doing a reload with includeACL set to true, we'll
either see if the XML already has an ACL element and instantiate an ACL with
it, or we'll get the ACL_REL link, invoke that, and return the result.

=cut

sub getACL {
  my $this = shift;

  unless ($this->{repository}->getCapabilities()->{'ACL'}) {
    throw WebService::Cmis::NotSupportedException("This repository does not support ACLs"); 
  }

  my $result;

  if ($this->{xmlDoc}->exists($CMIS_XPATH_ACL)) {
    ($result) = $this->{xmlDoc}->findnodes($CMIS_XPATH_ACL);
  } else {
    my $url = $this->getLink(ACL_REL);
    $result = $this->{repository}{client}->get($url) if $url;
  }

  return unless $result;

  require WebService::Cmis::ACL;
  return new WebService::Cmis::ACL(xmlDoc=>$result);
}


=back

=head1 AUTHOR

Michael Daum C<< <daum@michaeldaumconsulting.com> >>

=head1 COPYRIGHT AND LICENSE

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See L<perlartistic>.

=cut

1;

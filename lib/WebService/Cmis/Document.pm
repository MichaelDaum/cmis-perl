package WebService::Cmis::Document;

=head1 NAME

WebService::Cmis::Object

Representation of a cmis object

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

use strict;
use warnings;
use WebService::Cmis qw(:collections :contenttypes :namespaces :relations);
use WebService::Cmis::Object ();
use WebService::Cmis::NotImplementedException ();
use WebService::Cmis::NotSupportedException ();
use XML::LibXML qw(:libxml);
use Error qw(:try);
our @ISA = ('WebService::Cmis::Object');

our $CMIS_XPATH_CONTENT_LINK = new XML::LibXML::XPathExpression('./*[local-name() = "content" and namespace-uri() = "'.ATOM_NS.'"]/@src');
our $CMIS_XPATH_RENDITIONS = new XML::LibXML::XPathExpression('./*[local-name()="object" and namespace-uri()="'.CMISRA_NS.'"]/*[local-name()="rendition" and namespace-uri()="'.CMIS_NS.'"]');

=head1 METHODS

=over 4

=item checkOut -> $document

performs a checkOut on this document and returns the
Private Working Copy (PWC), which is also an instance of
Document

See CMIS specification document 2.2.7.1 checkOut

=cut

sub checkOut {
  my $this = shift;

  require WebService::Cmis::Property;

  # get the checkedout collection URL
  my $checkoutUrl = $this->{repository}->getCollectionLink(CHECKED_OUT_COLL);
  throw Error::Simple("Could not determine the checkedout collection url.") unless defined $checkoutUrl;

  # get this document's object ID
  # build entry XML with it
  my $entryXmlDoc = $this->{repository}->createEntryXmlDoc(
    properties => [
      WebService::Cmis::Property::newId(
        id=>"cmis:objectId",
        queryName=>"cmis:objectId",
        value=>$this->getId
      )
    ]
  );

  #print STDERR "entryXmlDoc=".$entryXmlDoc->toString(1)."\n";

  # post it to to the checkedout collection URL
  my $result = $this->{repository}{client}->post($checkoutUrl, $entryXmlDoc->toString, ATOM_XML_ENTRY_TYPE);

  # now that the doc is checked out, we need to refresh the XML
  # to pick up the prop updates related to a checkout
  $this->reload;

  return new WebService::Cmis::Document(repository=>$this->{repository}, xmlDoc=>$result);
}

=item isCheckedOut

Returns true if the document is checked out.

=cut

sub isCheckedOut {
  my $this = shift;

  # reloading the document just to make sure we've got the latest
  # and greatest checked out prop
  $this->reload;
  my $prop = $this->getProperties->{'cmis:isVersionSeriesCheckedOut'};
  return 0 unless defined $prop;
  return $prop->getValue;
}


=item getCheckedOutBy -> $userId

returns the ID who currently has the document checked out.

=cut

sub getCheckedOutBy {
  my $this = shift;
  # reloading the document just to make sure we've got the latest
  # and greatest checked out prop
  $this->reload;

  my $prop = $this->getProperties->{'cmis:versionSeriesCheckedOutBy'};
  return unless defined $prop;
  return $prop->getValue;
}

=item getPrivateWorkingCopy -> $cmisDocument

retrieves the object using the object ID in the property:
cmis:versionSeriesCheckedOutId then uses getObject to instantiate
the object.

=cut

sub getPrivateWorkingCopy {
  my $this = shift;

  # reloading the document just to make sure we've got the latest
  # and greatest PWC ID
  $this->reload;

  my $pwcDocId = $this->getProperty('cmis:versionSeriesCheckedOutId');
  return unless $pwcDocId;
  return $this->{repository}->getObject($pwcDocId);
}

=item cancelCheckOut

cancels the checkout of this object by retrieving the Private Working
Copy (PWC) and then deleting it. After the PWC is deleted, this object
will be reloaded to update properties related to a checkout.

See CMIS specification document 2.2.7.2 cancelCheckOut

=cut

sub cancelCheckOut {
  my $this = shift;

  my $pwcDoc = $this->getPrivateWorkingCopy;
  return unless defined $pwcDoc;
  $pwcDoc->delete;
  $this->reload;

  return $this;
}

=item checkIn($checkinComment, %params) -> $document

checks in this Document which must be a private
working copy (PWC).

See CMIS specification document 2.2.7.3 checkIn

The following optional arguments are supported:

=over 4

=item major
=item properties
=item contentStream
=item policies
=item addACEs
=item removeACEs

=back

TODO: support repositories without PWCUpdate capabilities

=cut

sub checkIn {
  my $this = shift;
  my $checkinComment = shift;

  # build an empty ATOM entry
  my $entryXmlDoc = $this->{repository}->createEmptyXmlDoc;

  # Get the self link
  # Do a PUT of the empty ATOM to the self link
  my $url = $this->getSelfLink;

  my $result = $this->{repository}{client}->put($url, $entryXmlDoc->toString, ATOM_XML_TYPE, 
    "checkin"=>'true', # SMELL: or is it CMIS-checkin
    "checkinComment"=>$checkinComment, # SMELL: or is it CMIS-checkinComment
    @_
  );

  return new WebService::Cmis::Document(repository=>$this->{repository}, xmlDoc=>$result);
}

=item getContentLink(%params) -> $url

returns the source link to this document

The params are added to the url.

=cut

sub getContentLink {
  my $this = shift;
  my %params = @_;

  my $url = $this->_getDocumentElement->find($CMIS_XPATH_CONTENT_LINK);
  $url = $this->getLink('enclosure') unless defined $url;
  return unless defined $url;
  $url = "".$url;

  my $gotUrlParams = ($url =~ /\?/)?1:0;

  foreach my $key (keys %params) {
    if ($gotUrlParams) {
      $url .= '&';
    } {
      $url .= '?';
      $gotUrlParams = 1;
    }
    $url .= $key.'='._urlEncode($params{$key});
  }

  return $url;
}

sub _urlEncode {
  my $text = shift;

  $text =~ s/([^0-9a-zA-Z-_.:~!*'\/])/'%'.sprintf('%02x',ord($1))/ge;

  return $text;
}

=item getContentStream

returns the CMIS service response from invoking the 'enclosure' link.

The optional argument:

=over 4

=item streamId: id of the content rendition

=back

See CMIS specification document 2.2.4.10 getContentStream

>>> doc.getName()
u'sample-b.pdf'
>>> o = open('tmp.pdf', 'wb')
>>> result = doc.getContentStream()
>>> o.write(result.read())
>>> result.close()
>>> o.close()
>>> import os.path
>>> os.path.getsize('tmp.pdf')
117248


# TODO: Need to implement the streamId

=cut

sub getContentStream {
  my $this = shift;
  
  my $url = $this->getContentLink;

  if ($url) {
    # if the url exists, follow that
    #print STDERR "url=$url\n";

    my $client = $this->{repository}{client};
    $client->GET($url, @_);

    my $code = $client->responseCode;
    return $client->responseContent if $code >= 200 && $code < 300;
    $client->processErrors;
  } else {
    # otherwise, try to return the value of the content element
    return $this->_getDocumentElement->findvalue("./*[local-name() = 'content' and namespace-uri() = '".ATOM_NS."']");
  }

  # never reach
  return;
}

=item getAllVersions(%params) -> $atomFeed

returns a AtomFeed` of document objects for the entire
version history of this object, including any PWC's.

See CMIS specification document 2.2.7.5 getAllVersions

The optional filter and includeAllowableActions are
supported.

=cut

sub getAllVersions {
  my $this = shift;

  # get the version history link
  my $versionsUrl = $this->getLink(VERSION_HISTORY_REL);

  # invoke the URL
  my $result = $this->{repository}{client}->get($versionsUrl, @_);

  # return the result set
  require WebService::Cmis::AtomFeed::Objects;
  return new WebService::Cmis::AtomFeed::Objects(repository=>$this->{repository}, xmlDoc=>$result);
}

=item getRenditions(%params) -> $binaryData

See CMIS specification document 2.2.4.11 getRenditions

The following optional arguments are currently supported:

=over 4

=item renditionFilter
=item maxItems
=item skipCount

=back

=cut

sub getRenditions {
  my $this = shift;

  # if Renditions capability is None, return notsupported
  unless ($this->{repository}->getCapabilities->{'Renditions'}) {
    throw WebService::Cmis::NotSupportedException("This repository does not support Renditions");
  }

  throw WebService::Cmis::NotImplementedException;
}

=item getRenditionInfo -> %renditionInfo

returns a hash of all known renditions for this CMIS document.

=cut

sub getRenditionInfo {
  my $this = shift;

  # if Renditions capability is None, return notsupported
  unless ($this->{repository}->getCapabilities->{'Renditions'}) {
    throw WebService::Cmis::NotSupportedException("This repository does not support Renditions");
  }

  unless ($this->{renditionInfo}) {
    unless ($this->_getDocumentElement->exists($CMIS_XPATH_RENDITIONS)) {
      # reload including renditions
      $this->reload(renditionFilter=>'*');
    }
    $this->{renditionInfo} = ();
    foreach my $node ($this->_getDocumentElement->findnodes($CMIS_XPATH_RENDITIONS)) {
      my $rendition = ();
      foreach my $child ($node->childNodes) {
        next unless $child->nodeType == XML_ELEMENT_NODE;
        my $key = $child->localname;
        my $val = $child->string_value;
        #print STDERR "key=$key, value=".($val||'undef')."\n";
        $rendition->{$key} = $val;
      }
      $this->{renditionInfo}{$rendition->{streamId}} = $rendition;
    }
  }

  return $this->{renditionInfo};
}

=item getRenditionLink(%params)

returns a link to the documents rendition

Use the renditions properties to get a specific one:

=over 4

=item mimetype
=item kind
=item height
=item width
=item length
=item title

=back

=cut

sub getRenditionLink {
  my $this = shift;
  my %params = @_;

  # if Renditions capability is None, return notsupported
  unless ($this->{repository}->getCapabilities->{'Renditions'}) {
    throw WebService::Cmis::NotSupportedException("This repository does not support Renditions");
  }

  my $renditions = $this->getRenditionInfo;
  foreach my $rendi (values %$renditions) {
    my $found = 1;
    foreach my $key (keys %params) {
      if (defined $rendi->{$key} && $rendi->{$key} !~ /$params{$key}/i) {
        $found = 0;
        last;
      }
    }
    next unless $found;

    return $this->getContentLink(streamId=>$rendi->{streamId});
  }

  return;
}

=item getLatestVersion(%params) -> $document

returns a cmis Document representing the latest version in the version series.

See CMIS specification document 2.2.7.4 getObjectOfLatestVersion

The following optional arguments are supported:

=over 4

=item major
=item filter
=item includeRelationships
=item includePolicyIds
=item renditionFilter
=item includeACL
=item includeAllowableActions

=back

  $latestDoc = $doc->getLatestVersion;
  $latestDoc = $doc->getLatestVersion(major=>1);

  print $latestDoc->getProperty("cmis:versionLabel")."\n";

=cut

sub getLatestVersion {
  my $this = shift;
  my %params = @_;
        
  my $major = delete $params{major};
  $params{returnVersion} = $major?'latestmajor':'latest';

  return $this->{repository}->getObject($this->getId, %params);
}

=item copy($targetFolder, $propertyList, $versionState) -> $cmisDocument

Creates a document object as a copy of the given source document in the (optionally) 
specified location. 

The $targetFolder specifies the folder that becomes the parent
of the new document. This parameter must be specified if the repository does not
have the "unfiling" capability.

The $propertyList is a list of WebService::Cmis::Property objects optionally specifieds
the propeties about to change in the newly created Document object.

Valid values for $versionState are:

=over 4

=item "none": the document is created as a non-versionable object

=item "checkedout": the document is created in checked-out state

=item "major" (default): the document is created as a new major version

=item "minor": the document is created as a minor version

=back

See CMIS specification document 2.2.4.2 (createDocumentFromSource)

The following optional arguments are not yet supported:

=over 4

=item policies
=item addACEs
=item removeACEs

=back

TODO: This is not yet implemented.

=cut

sub copy { throw WebService::Cmis::NotImplementedException; }

=item getPropertiesOfLatestVersion

TODO: This is not yet implemented.

=cut

sub getPropertiesOfLatestVersion { throw WebService::Cmis::NotImplementedException; }

=item setContentStream

TODO: This is not yet implemented.

=cut

sub setContentStream { throw WebService::Cmis::NotImplementedException; }

=item deleteContentStream

TODO: This is not yet implemented.

=cut

sub deleteContentStream { throw WebService::Cmis::NotImplementedException; }

=back

=head1 COPYRIGHT AND LICENSE

Copyright 2012 Michael Daum

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See F<http://dev.perl.org/licenses/artistic.html>.

=cut

1;

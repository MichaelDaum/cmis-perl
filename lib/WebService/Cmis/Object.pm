package WebService::Cmis::Object;

=head1 NAME

WebService::Cmis::Object

Representation of a cmis object

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

use strict;
use warnings;
use WebService::Cmis qw(:namespaces :relations :contenttypes :collections);
use XML::LibXML qw(:libxml);
use WebService::Cmis::NotImplementedException;
use Error qw(:try);
use WebService::Cmis::AtomEntry ();

our @ISA = qw(WebService::Cmis::AtomEntry);

our %classOfBaseTypeId = (
  'cmis:folder' => 'WebService::Cmis::Folder',
  'cmis:document' => 'WebService::Cmis::Document',
  'cmis:relationship' => 'WebService::Cmis::Relationship',
  'cmis:policy' => 'WebService::Cmis::Policy',
);

our $CMIS_XPATH_PROPERTIES = new XML::LibXML::XPathExpression('./*[local-name()="object" and namespace-uri()="'.CMISRA_NS.'"]/*[local-name()="properties" and namespace-uri()="'.CMIS_NS.'"]/*[@propertyDefinitionId]');
our $CMIS_XPATH_ALLOWABLEACTIONS = new XML::LibXML::XPathExpression('./*[local-name() = "object" and namespace-uri()="'.CMISRA_NS.'"]/*[local-name() = "allowableActions" and namespace-uri() ="'.CMIS_NS.'"]');

=head1 METHODS

=over 4

=item new(repository=>$repository, xmlDoc=>$xmlDoc) -> $object

constructor to get a specialized object, a subclass of WebService::Cmis::Object
representing a cmis:document, cmis:folder, cmis:relationship or cmis:policy.

=cut

sub new {
  my $class = shift;

  my $obj = $class->SUPER::new(@_);

  my $baseTypeId = $obj->getProperty("cmis:baseTypeId");
  return $obj unless $baseTypeId;

  my $subClass = $classOfBaseTypeId{$baseTypeId};
  return $obj unless $subClass;

  eval "use $subClass";
  if ($@) {
    throw Error::Simple($@);
  }

  return bless($obj, $subClass);
}



=item _initData

resets the internal cache of this entry.

=cut

sub _initData {
  my $this = shift;

  $this->SUPER::_initData;

  undef $this->{properties};
  undef $this->{allowableActions};
}

=item DESTROY 

clean up internal caches

=cut

sub DESTROY {
  my $this = shift;

  #print STDERR "called Object::DESTROY\n";

  $this->_initData;

  undef $this->{xmldoc};
  undef $this->{repository};
}

=item reload(%params) 

Fetches the latest representation of this object from the CMIS service.
Some methods, like document->checkout do this for you.

If you call reload with a properties filter, the filter will be in
effect on subsequent calls until the filter argument is changed. To
reset to the full list of properties, call reload with filter set to
'*'.

=cut

sub reload {
  my ($this, %params) = @_;

  throw Error::Simple("can't reload Object without an id or xmlDoc") unless defined $this->{id} || defined $this->{xmlDoc};

  #print STDERR "reload this:\n".join("\n", map("   ".$_."=".($this->{$_}||'undef'), keys %$this))."\n";

  my $byObjectIdUrl = $this->{repository}->getUriTemplate('objectbyid');

  require WebService::Cmis::Property::Boolean;

  $byObjectIdUrl =~ s/{id}/$this->getId()/ge;
  $byObjectIdUrl =~ s/{filter}/$params{filter}||''/ge;
  $byObjectIdUrl =~ s/{includeAllowableActions}/WebService::Cmis::Property::Boolean->unparse($params{includeAllowableActions}||'false')/ge;
  $byObjectIdUrl =~ s/{includePolicyIds}/WebService::Cmis::Property::Boolean->unparse($params{includePolicyIds}||'false')/ge;
  $byObjectIdUrl =~ s/{includeRelationships}/WebService::Cmis::Property::Boolean->unparse($params{includeRelationships}||'')/ge;
  $byObjectIdUrl =~ s/{includeACL}/WebService::Cmis::Property::Boolean->unparse($params{includeACL}||'false')/ge;
  $byObjectIdUrl =~ s/{renditionFilter}/$params{renditionFilter}||''/ge;

  # auto clear cache
  $this->{repository}{client}->clearCache;
  
  $this->{xmlDoc} = $this->{repository}{client}->get($byObjectIdUrl, %{$this->{extra_params}});
  $this->_initData;
}

=item getId() -> $id


returns the object ID for this object.

=cut

sub getId {
  my $this = shift;

  unless (defined $this->{id}) { # CAUTION: we must cache this to prevent deep recursion
    $this->{id} = $this->getProperty("cmis:objectId");
  }

  return $this->{id};
}

=item getName() -> $name

returns the cmis:name property.

=cut

sub getName {
  return $_[0]->getProperty("cmis:name");
}


=item getPath() -> $path

returns the cmis:path property.

=cut

sub getPath {
  return $_[0]->getProperty("cmis:path");
}

=item getTypeId() -> $typeId

returns the cmis:objectTypeId property.

=cut

sub getTypeId {
  return $_[0]->getProperty("cmis:objectTypeId");
}

=item getProperties() -> %properties;

returns a hash of the object's properties. If CMIS returns an
empty element for a property, the property will be in the
hash with an undef value

See CMIS specification document 2.2.4.8 getProperties

=cut

sub getProperties {
  my ($this, $filter) = @_;

  require WebService::Cmis::Property;
  unless (defined $this->{properties}) {
    foreach my $propNode ($this->_getDocumentElement->findnodes($CMIS_XPATH_PROPERTIES)) {
      my $property = WebService::Cmis::Property::load($propNode);
      #print STDERR "property = ".$property->toString."\n";
      $this->{properties}{$property->getId} = $property;
    }
  }

  return $this->{properties} if !defined($filter) || $filter eq '*';

  my $filterPattern;
  if (defined $filter && $filter ne '*') {
    $filterPattern = '^('.join('|', map {(($_ =~ /^.+:.+$/)? $_: 'cmis:'.$_)} split(/\s*,\s*/, $filter)).')$';
    #print STDERR "filterPattern=$filterPattern\n";
  }

  my %filteredProps = map {$_ => $this->{properties}{$_}} grep {/$filterPattern/} keys %{$this->{properties}};
  return \%filteredProps;
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

=item getAllowableActions() -> %allowableActions

returns a dictionary of allowable actions, keyed off of the action name.
See CMIS specification document 2.2.4.6 getAllowableActions

=cut

sub getAllowableActions { 
  my $this = shift;

  unless (defined $this->{allowableActions}) {
    $this->reload('includeAllowableActions' => 1); #SMELL: use the allowableActions link
    require WebService::Cmis::Property::Boolean;

    my ($allowNode) = $this->_getDocumentElement->findnodes($CMIS_XPATH_ALLOWABLEACTIONS);
    if ($allowNode) {
      foreach my $node ($allowNode->childNodes) {
        next unless $node->nodeType == XML_ELEMENT_NODE;
        $this->{allowableActions}{$node->localname} = WebService::Cmis::Property::Boolean->parse($node->string_value);
      } 
    }
  }

  return $this->{allowableActions};
}

=item getACL() 

repository->getCapabilities()->{'ACL'} must return manage or discover.

See CMIS specification document 2.2.10.1 getACL

The optional onlyBasicPermissions argument is currently not supported.

=cut

sub getACL {
  my $this = shift;

  unless ($this->{repository}->getCapabilities()->{'ACL'}) {
    throw WebService::Cmis::NotSupportedException("This repository does not support ACLs"); 
  }

  require WebService::Cmis::ACL;

  my $url = $this->getLink(ACL_REL);
  #print STDERR "acl url = $url\n";

  my $result = $this->{repository}{client}->get($url);

  return new WebService::Cmis::ACL(xmlDoc=>$result);
}

=item getSelfLink -> $href

returns the URL used to retrieve this object.

=cut

sub getSelfLink {
  return $_[0]->getLink(SELF_REL);
}

=item getAppliedPolicies(%params) -> $atomFeed

returns the list of policies applied to this object.

See CMIS specification document 2.2.9.3 getAppliedPolicies

=cut

sub getAppliedPolicies { 
  my $this = shift;

  # depends on this object's canGetAppliedPolicies allowable action
  unless ($this->getAllowableActions->{'canGetAppliedPolicies'}) {
    throw WebService::Cmis::NotSupportedException('This object has canGetAppliedPolicies set to false'); 
  }

  my $url = $this->getLink(POLICIES_REL, @_);
  unless ($url) {
     throw Error::Simple('could not determine policies URL'); # SMELL: use custom exception
  }

  my $result = $this->{repository}{client}->get($url, @_);

  # return the result set
  require WebService::Cmis::AtomFeed::Objects;
  return new WebService::Cmis::AtomFeed::Objects(repository=>$this->{repository}, xmlDoc=>$result);
}

=item getObjectParents -> $atomFeedOrEntry

gets the parent(s) for the specified non-folder, fileable object.
This is either an AtomFeed or an AtomEntry object depending on the "up" relation.

See CMIS specification document 2.2.3.5 getObjectParents

The following optional arguments are supported:

=over 4

=item filter
=item includeRelationships
=item renditionFilter
=item includeAllowableActions
=item includeRelativePathSegment

=back

=cut

sub getObjectParents {
  my $this = shift;

  # get the appropriate 'up' link
  my $parentUrl = $this->getLink(UP_REL);

  unless ($parentUrl) {
    throw WebService::Cmis::NotSupportedException('object does not support getObjectParents');
  }

  # invoke the URL
  my $result = $this->{repository}{client}->get($parentUrl, @_);

  if ($result->documentElement->localName eq 'feed') {
    # return the result set
    require WebService::Cmis::AtomFeed::Objects;
    return new WebService::Cmis::AtomFeed::Objects(repository=>$this->{repository}, xmlDoc=>$result);
  } else {
    # return the result set
    return new WebService::Cmis::Object(repository=>$this->{repository}, xmlDoc=>$result);
  }
}

=item getRelationships(%params) -> $atomFeed

returns a result set of relationship objects for each relationship where the
source is this object.

See CMIS specification document 2.2.8.1 getObjectRelationships

The following optional arguments are supported:

=over 4

=item includeSubRelationshipTypes
=item relationshipDirection
=item typeId
=item maxItems
=item skipCount
=item filter
=item includeAllowableActions

=back

=cut

sub getRelationships {
  my $this = shift;

  my $url = $this->getLink(RELATIONSHIPS_REL);

  unless ($url) {
     throw Error::Simple('could not determine relationships URL'); # SMELL: use custom exception
  }

  my $result = $this->{repository}{client}->get($url, @_);

  # return the result set
  require WebService::Cmis::AtomFeed::Objects;
  return new WebService::Cmis::AtomFeed::Objects(repository=>$this->{repository}, xmlDoc=>$result);
}

=item delete(%params)

Deletes this cmis object from the repository. Note that in the
case of a Folder object, some repositories will refuse to
delete it if it contains children and some will delete it without
complaint. If what you really want to do is delete the folder and all
of its descendants, use Folder->deleteTree instead.

See CMIS specification document 2.2.4.14 delete

=cut

sub delete {
  my $this = shift;

  my $url = $this->getSelfLink;
  my $result = $this->{repository}{client}->delete($url, @_);

  return $result;
}

=item move($sourceFolder, $targetFolder) -> $this

Moves the specified file-able object from one folder to another. 

See CMIS specification document 2.2.4.13 move

=cut

sub move { 
  my ($this, $sourceFolder, $targetFolder) = @_;

  my $targetUrl = $targetFolder->getLink(DOWN_REL, ATOM_XML_FEED_TYPE_P);

  if ($sourceFolder) {
    my $uri = new URI($targetUrl);
    my %queryParams = ($uri->query_form, sourceFolderId=>$sourceFolder->getId);
    $uri->query_form(%queryParams);
    $targetUrl = $uri->as_string;
  }

  # post it to to the checkedout collection URL
  my $result = $this->{repository}{client}->post($targetUrl, $this->_xmlDoc->toString, ATOM_XML_ENTRY_TYPE);

  # now that the doc is moved, we need to refresh the XML
  # to pick up the prop updates related to the move
  $this->{xmlDoc} = $result;
  $this->_initData;

  #return new WebService::Cmis::Object(repository=>$this->{repository}, xmlDoc=>$result);
  return $this;
}

=item moveTo($targetFolder) -> $this

Convenience function to move an object from its parent folder to a given target folder.
Same as Folder::addObject but in reverse logic

=cut

sub moveTo {
  my ($this, $targetFolder) = @_;

  my $parents = $this->getObjectParents;
  my $parentFolder;

  if ($parents->isa("WebService::Cmis::AtomFeed")) {
    $parentFolder = $parents->getNext; #SMELL: what if there are multiple parents
  } else {
    $parentFolder = $parents;
  }

  return $this->move($parentFolder, $targetFolder);
}

=item unfile($folder)

removes this object from the given parent folder.
If the $folder parameter is not provided, the document is removed from any of its parent folders.

See CMIS specification document 2.2.5.2

=cut

sub unfile {
  my $this = shift;
  my $folder = shift;

  unless ($this->{repository}->getCapabilities()->{'Unfiling'}) {
    throw WebService::Cmis::NotSupportedException("This repository does not support unfiling");
  }

  my $unfiledLink = $this->{repository}->getCollectionLink(UNFILED_COLL, ATOM_XML_FEED_TYPE_P);

  if ($folder) {
    my $uri = new URI($unfiledLink);
    my %queryParams = ($uri->query_form, folderId=>$folder->getId);
    $uri->query_form(%queryParams);
    $unfiledLink = $uri->as_string;
  }

  # post it to to the unfiled collection URL
  my $result = $this->{repository}{client}->post($unfiledLink, $this->_xmlDoc->toString, ATOM_XML_ENTRY_TYPE);

  # now that the doc is moved, we need to refresh the XML
  # to pick up the prop updates related to the move
  $this->reload;

  #return new WebService::Cmis::Object(repository=>$this->{repository}, xmlDoc=>$result);
  return $this;
}

=item updateProperties($propertyList) -> $this

Updates the properties of an object with the properties provided.
Only provide the set of properties that need to be updated.

See CMIS specification document 2.2.4.12 updateProperties

  $folder = $repo->getObjectByPath('/SomeFolder');
  $folder->getName; # returns SomeFolder

  $folder->updateProperties([
    WebService::Cmis::Property::newString(
      id => 'cmis:name',
      value => 'SomeOtherName',
    ),
  ]);

  $folder->getName; # returns SomeOtherName


TODO: The optional changeToken is not yet supported.

=cut

sub updateProperties {
  my $this = shift;

  # get the self link
  my $selfUrl = $this->getSelfLink;

  # build the entry based on the properties provided
  my $xmlEntryDoc = $this->{repository}->createEntryXmlDoc(properties => (@_));

  # do a PUT of the entry
  my $result = $this->{repository}{client}->put($selfUrl, $xmlEntryDoc->toString, ATOM_XML_TYPE);

  # reset the xmlDoc for this object with what we got back from
  # the PUT, then call initData we dont' want to call
  # self.reload because we've already got the parsed XML--
  # there's no need to fetch it again

  $this->{xmlDoc} = $result;
  $this->_initData;

  return $this;
}

=item rename($string) -> $this

rename this object updating its cmis:properties

=cut

sub rename {
  return $_[0]->updateProperties([
    WebService::Cmis::Property::newString(
      id => 'cmis:name',
      value => $_[1],
    ),
  ]);
}

=item updateSummary($text) -> $this

changes the atom:summary of this object 

=cut

sub updateSummary {
  my ($this, $text) = @_;

  # get the self link
  my $selfUrl = $this->getSelfLink;

  # build the entry based on the properties provided
  my $xmlEntryDoc = $this->{repository}->createEntryXmlDoc(summary => $text);

  # do a PUT of the entry
  my $result = $this->{repository}{client}->put($selfUrl, $xmlEntryDoc->toString, ATOM_XML_TYPE);

  # reset the xmlDoc for this object with what we got back from
  # the PUT, then call initData we dont' want to call
  # self.reload because we've already got the parsed XML--
  # there's no need to fetch it again

  $this->{xmlDoc} = $result;
  $this->_initData;

  return $this;
}


sub applyACL { throw WebService::Cmis::NotImplementedException; }
sub applyPolicy { throw WebService::Cmis::NotImplementedException; }
sub createRelationship { throw WebService::Cmis::NotImplementedException; }
sub removePolicy { throw WebService::Cmis::NotImplementedException; }

=back

=head1 AUTHOR

Michael Daum C<< <daum@michaeldaumconsulting.com> >>

=head1 COPYRIGHT AND LICENSE

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See L<perlartistic>.

=cut

1;

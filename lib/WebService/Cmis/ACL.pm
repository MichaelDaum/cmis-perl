package WebService::Cmis::ACL;

=head1 NAME

WebService::Cmis::ACL

Representation of a cmis ACL object

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

use strict;
use warnings;
use WebService::Cmis qw(:namespaces);
use WebService::Cmis::ACE ();
use XML::LibXML qw(:libxml);
use Error qw(:try);

=head1 METHODS

=over 4

=item new(I<%args>)

=cut

sub new {
  my $class = shift;

  my $this = bless({ @_ }, $class);

  if (defined $this->{xmlDoc}) {
    $this->{entries} = $this->_getEntriesFromXml();
  }
  
  return $this;
}

=item DESTROY

destructor for this ACL object

=cut

sub DESTROY {
  my $this = shift;

  undef $this->{xmlDoc};
  undef $this->{entries};
}

=item toString()

return a string representation of this object

=cut

sub toString {
  my $this = shift;

  my @result = ();
  foreach my $ace ($this->getEntries) {
    push @result, $ace->toString;
  }

  return join("\n", @result);
}

=item addEntry($ace)

adds an ACE entry to the ACL.

=cut

sub addEntry {
  my ($this, $ace) = @_;

  $this->{entries}{$ace->{principalId}} = $ace;
}

=item removeEntry($principalId) -> $ace;

removes the ACE entry given a specific principalId.

=cut

sub removeEntry {
  my ($this, $principalId) = @_;

  return delete $this->{entries}{$principalId};
}

=item getEntries -> @aces

returns a list of ACE objects for each access control
entry in the ACL. 

=cut

sub getEntries {
  my $this = shift;

  unless (defined $this->{entries}) {
    $this->{entries} = $this->_getEntriesFromXml();
  }

  return @{$this->{entries}};
}

# private helper to for getting all ACEs for the XML representation of this ACL
sub _getEntriesFromXml {
  my $this = shift;

  throw Error::Simple("no xmldoc for ACL object") unless defined $this->{xmlDoc};

  my @result = ();
  my ($aclNode) = $this->{xmlDoc}->getElementsByTagNameNS(CMIS_NS, 'acl'); # ok

  foreach my $node ($aclNode->childNodes) {
    next unless $node->nodeType == XML_ELEMENT_NODE && $node->localname eq 'permission';

    my $principalId = $node->findvalue('./cmis:principal/cmis:principalId');
    my $direct = $node->findvalue('./cmis:direct');
    my @perms = $node->findvalue('./cmis:permission');

    #print STDERR "principalId=$principalId, direct=$direct, perms=".join(', ', @perms)."\n";

    # create an ACE
    push @result, new WebService::Cmis::ACE(
      principalId => $principalId, 
      permissions => \@perms, 
      direct => $direct
    );
  }

  return \@result;
}

=item getXmlDoc -> $xmlDoc

This method rebuilds the local XML representation of the ACL based on
the ACE objects in the entries list and returns the resulting
XML Document.

=cut

sub getXmlDoc {
  my $this = shift;

  return unless defined $this->{entries} && scalar(@{$this->{entries}});

  my $xmlDoc = new XML::LibXML::Document('1.0', 'UTF-8');

  my $aclNode = $xmlDoc->createElementNS(CMIS_NS, 'cmis:acl');
  $aclNode->setAttribute('xmlns:cmis', CMIS_NS);

  foreach my $ace ($this->getEntries) {
    my $permNode = $xmlDoc->createElementNS(CMIS_NS, 'cmis:permission');

    # principalId
    $permNode->addNewChild(CMIS_NS, 'principal')
      ->addNewChild(CMIS_NS, 'principalId')
      ->addChild($xmlDoc->createTextNode($ace->{principalId}));

    # direct
    $permNode->addNewChild(CMIS_NS, 'direct')
      ->addChild($xmlDoc->createTextNode($ace->{direct}));

    # permissions
    foreach my $perm (@{$ace->{permissions}}) {
      $permNode->addNewChild(CMIS_NS, 'permission')
        ->addChild($xmlDoc->createTextNode($perm));
    }

    $aclNode->appendChild($permNode);
  }
  
  $xmlDoc->setDocumentElement($aclNode);
  return $this->{xmlDoc} = $xmlDoc;
}

1;

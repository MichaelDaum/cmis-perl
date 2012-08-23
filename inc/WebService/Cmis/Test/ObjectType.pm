package WebService::Cmis::Test::ObjectType;
use base qw(WebService::Cmis::Test);
use Test::More;

use strict;
use warnings;

use Error qw(:try);

sub test_ObjectType : Tests {
  my $this = shift;

  my $repo = $this->getRepository;

  my $typeDefs = $repo->getTypeDefinitions;
  isa_ok($typeDefs, 'WebService::Cmis::AtomFeed::ObjectTypes');

  my $size = $typeDefs->getSize;
  note("found $size type definitions");

  $this->num_tests($size*18+1);

  while (my $objectType = $typeDefs->getNext) {
    isa_ok($objectType, 'WebService::Cmis::ObjectType');

    #print STDERR "attributes=".join(", ", keys %{$objectType->getAttributes})."\n";

    my $id = $objectType->getId;
    my $displayName = $objectType->getDisplayName;
    my $description = $objectType->getDescription;
    my $link = $objectType->getLink;
    my $baseId = $objectType->getBaseId;
    my $localName = $objectType->getLocalName;
    my $localNamespace = $objectType->getLocalNamespace;
    my $queryName = $objectType->getQueryName;
    my $contentStreamAllowed = $objectType->getContentStreamAllowed || '';

    my $isCreatable = $objectType->isCreatable;
    my $isFileable = $objectType->isFileable;
    my $isQueryable = $objectType->isQueryable;
    my $isFulltextIndexed = $objectType->isFulltextIndexed;
    my $isIncludedInSupertypeQuery = $objectType->isIncludedInSupertypeQuery;
    my $isControllablePolicy = $objectType->isControllablePolicy;
    my $isControllableACL = $objectType->isControllableACL;
    my $isVersionable = $objectType->isVersionable;

#   print STDERR "id=$id ($objectType->{attributes}{id})\n";
#   print STDERR "  displayName=$displayName\n";
#   print STDERR "  description=$description\n";
#   print STDERR "  link=$link\n";
#   print STDERR "  baseId=$baseId\n";
#   print STDERR "  localName=$localName\n";
#   print STDERR "  localNamespace=$localNamespace\n";
#   print STDERR "  queryName=$queryName\n";
#   print STDERR "  contentStreamAllowed=$contentStreamAllowed\n";
#
#   print STDERR "  isCreatable=$isCreatable\n";
#   print STDERR "  isFileable=$isFileable\n";
#   print STDERR "  isQueryable=$isQueryable\n";
#   print STDERR "  isFulltextIndexed=$isFulltextIndexed\n";
#   print STDERR "  isIncludedInSupertypeQuery=$isIncludedInSupertypeQuery\n";
#   print STDERR "  isControllablePolicy=$isControllablePolicy\n";
#   print STDERR "  isControllableACL=$isControllableACL\n";
#   print STDERR "  isVersionable=$isVersionable\n";

    $objectType->reload;
    #print STDERR "2 - id=".$objectType->getId.", displayName=".$objectType->getDisplayName.", description=".$objectType->getDescription.", link=".$objectType->getLink."\n";

    is($id, $objectType->getId);
    is($displayName, $objectType->getDisplayName);
    is($description, $objectType->getDescription);
    is($link, $objectType->getLink);
    is($baseId, $objectType->getBaseId);
    is($localName, $objectType->getLocalName);
    is($localNamespace, $objectType->getLocalNamespace);
    is($queryName, $objectType->getQueryName);
    is($contentStreamAllowed, ($objectType->getContentStreamAllowed||''));

    is($isCreatable, $objectType->isCreatable);
    is($isFileable, $objectType->isFileable);
    is($isQueryable, $objectType->isQueryable);
    is($isFulltextIndexed, $objectType->isFulltextIndexed);
    is($isIncludedInSupertypeQuery, $objectType->isIncludedInSupertypeQuery);
    is($isControllablePolicy, $objectType->isControllablePolicy);
    is($isControllableACL, $objectType->isControllableACL);
    is($isVersionable, $objectType->isVersionable);
  }
}


1;

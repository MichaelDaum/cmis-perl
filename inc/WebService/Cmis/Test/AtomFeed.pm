package WebService::Cmis::Test::AtomFeed;
use base qw(WebService::Cmis::Test);

use strict;
use warnings;

use Test::More;
use Error qw(:try);
use WebService::Cmis qw(:collections :utils :relations :namespaces :contenttypes);

sub test_AtomFeed : Tests {
  my $this = shift;

  my $repo = $this->getRepository;

  my $resultSet = $repo->getCollection(ROOT_COLL);
  my $nrResults = $resultSet->getSize;
  ok($nrResults > 0) or diag("no objects in root collection");
  #print STDERR "found $nrResults results\n";

  while(my $obj = $resultSet->getNext) {
    isa_ok($obj, "WebService::Cmis::Object");
    #print STDERR "name=".$obj->getName." type=".$obj->getTypeId." path=".($obj->getPath||'')."\n";
    #print STDERR "toString=".$obj->toString."\n";
    ok(defined $obj->getName);
    ok(defined $obj->getTypeId);
    ok(defined $obj->toString);
    if ($obj->isa("WebService::Cmis::Folder")) {
      ok(defined $obj->getPath);
      like($obj->getPath, qr"^/");
      my $regex = $obj->getName.'$';
      like($obj->getPath, qr/$regex/);
    }
    ok(!ref($obj->toString)) or diag("illegal objectId");
  }
}

# self link on xCmis broken
sub test_AtomFeed_rewind : Test {
  my $this = shift;

  my $repo = $this->getRepository;

  my $resultSet = $repo->getCollection(ROOT_COLL);
  my $size1 = $resultSet->getSize;
  #print STDERR "resultSet1=".$resultSet->{xmlDoc}->toString(1)."\n";

  $resultSet->rewind;
  #print STDERR "resultSet2=".$resultSet->{xmlDoc}->toString(1)."\n";

  my $size2 = $resultSet->getSize;

  #print STDERR "size1=$size1, size2=$size2\n";

  is($size1, $size2);
}

sub test_AtomFeed_getSelfLinks_RootCollection : Tests {
  my $this = shift;
  my $repo = $this->getRepository;
  my $collection = $repo->getCollection(ROOT_COLL);
  my $nrEntries = $collection->getSize;
  #print STDERR "found $nrEntries objects in root collection\n";
  #print STDERR "self url of collection=".$collection->getLink(SELF_REL)."\n";

  my $index = 0;
  if ($collection->getSize > 0) {
    my $obj = $collection->getNext;
    ok(defined $obj) or diag("no object found in non-zero feed");
    do {
      isa_ok($obj, "WebService::Cmis::Object");
      my $id = $obj->getId;
      my $url = $obj->getSelfLink;
      my $name = $obj->getName;
      my $summary = $obj->getSummary;
      ok(defined $id);
      ok(defined $url);
      ok(defined $name);
      ok(defined $summary);
      #print STDERR "name=$name, summary=$summary, url=$url\n";
      $id =~ s/^.*\///;
      $url =~ s/^.*\///;
      is($url, $id) or diag("url suffix '$url' doesn't match id suffix '$id'");
      $index++;
    } while ($obj = $collection->getNext);
  }

  is($nrEntries, $index);
}

sub test_AtomFeed_getSelfLinks_getDescendants : Tests {
  my $this = shift;
  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;
  my $resultSet = $root->getDescendants(depth=>2);
  #print STDERR "found ".$resultSet->getSize." objects in result set\n";
  #print STDERR "self url of result set=".$resultSet->getLink(SELF_REL)."\n";

  while(my $obj = $resultSet->getNext) {
    isa_ok($obj, "WebService::Cmis::Object");
    my $id = $obj->getId;
    my $url = $obj->getSelfLink;
    #print STDERR "name=$name, id=$id, url=$url\n";
    $id =~ s/^.*\///;
    $url =~ s/^.*\///;
    is($url, $id) or diag("url suffix '$url' doesn't match id suffix '$id'");
  }
}

sub test_AtomFeed_reverse : Tests {
  my $this = shift;
  my $repo = $this->getRepository;
  my $collection = $repo->getCollection(ROOT_COLL);
  my $nrEntries = $collection->getSize;
  #print STDERR "found $nrEntries objects in root collection\n";

  my $index = 0;
  if ($collection->getSize > 0) {
    $collection->fastforward;
    #print STDERR  "1 - index=$collection->{index}\n";
    
    my $obj = $collection->getPrev;

    #print STDERR  "2 - index=$collection->{index}\n";
    my $lastObj = $obj;

    #print STDERR "lastObj=".$lastObj->toString."\n";
    ok(defined $obj) or diag("no object found in non-zero feed");

    do {
      isa_ok($obj, "WebService::Cmis::Object");
      $index++;

      ok($collection->{index} >= 0) or diag("illegal index in AtomFeed");

      $obj = $collection->getPrev;
      #print STDERR  "3 - index=$collection->{index}\n";

      #print STDERR "obj=".$obj->toString."\n";
      if ($obj) {
        isnt($obj->toString, $lastObj->toString) or diag("can't travel backwards in atom feed");
      }

    } while ($obj);
  }

  is($nrEntries, $index);
}

sub test_AtomFeed_paging : Tests {
  my $this = shift;
  my $repo = $this->getRepository;

  my $changes1;
  my $error;
  
  try {
    $changes1 = $repo->getContentChanges;
  } catch WebService::Cmis::ClientException with {
    $error = shift;
    ok(ref($error));
    isa_ok($error, "WebService::Cmis::ClientException");
    like($error, qr/^401 Unauthorized/);
  };
  return $error if defined $error;

  my $size = $changes1->getSize;

  #print STDERR "size1=$size\n";
  #print STDERR "### changes:\n".$changes1->{xmlDoc}->toString(1)."\n###\n";

  my %entries1 = ();
  my @keys = ();
  while (my $entry = $changes1->getNext) {
    my $id = $entry->getId;
    my $changeTime = $entry->getChangeTime;
    my $key = "$id-$changeTime";
    #print STDERR "key1=$key\n";
    push @keys, $key;

    ok(defined $entries1{$key});
    $entries1{$key} = $entry;
  }

  #print STDERR "index1=".scalar(keys %entries1)."\n";

  my $changes2 = $repo->getContentChanges(maxItems=>10);
  my $size2 = $changes2->getSize;
  #print STDERR "size2=$size2\n";

  my %entries2 = ();
  while (my $entry = $changes2->getNext) {
    my $id = $entry->getId;
    my $changeTime = $entry->getChangeTime;
    my $key = "$id-$changeTime";
    #print STDERR "key2=$key\n";

    ok(defined $entries2{$key});
    $entries2{$key} = $entry;
  }

  #print STDERR "index2=".scalar(keys %entries2)."\n";

  foreach my $key (@keys) {
    #print STDERR "key=$key\n";
    ok(defined $entries2{$key}) or diag("entry $key in first set not found in second");
  }
}


1;

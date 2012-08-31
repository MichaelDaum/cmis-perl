package WebService::Cmis::Test::Document;
use base qw(WebService::Cmis::Test);

use strict;
use warnings;

use Error qw(:try);
use Test::More;
use WebService::Cmis qw(:collections :utils :relations :namespaces :contenttypes);

sub _getParents {
  my $parents = $_[0]->getObjectParents;

  my @parents = ();
  if ($parents->isa("WebService::Cmis::AtomFeed")) {
    #note("nr parents : ".$parents->getSize);
    push @parents, $_ while $_ = $parents->getNext;
  } else {
    push @parents, $parents;
  }

  return @parents;
}

sub _saveFile {
  my ($name, $text) = @_;
  my $FILE;
  unless (open($FILE, '>', $name)) {
    die "Can't create file $name - $!\n";
  }
  print $FILE $text;
  close($FILE);
}

sub test_Document_getAllVersions : Tests {
  my $this = shift;
  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;
  my $resultSet = $root->getDescendants(depth=>2);

  ok(defined $resultSet) or diag("can't fetch results");

  note("found ".$resultSet->getSize." documents in root collection");

  while(my $obj = $resultSet->getNext) {
    next unless $obj->isa("WebService::Cmis::Document");

    note("versions in ".$obj->getId.", url=".$obj->getSelfLink);
    my $allVersions = $obj->getAllVersions;
    ok(defined $allVersions);
    ok($allVersions->getSize > 0) or diag("no versions for ".$obj->toString);

    while(my $version = $allVersions->getNext) {
      note("version=".$version->toString);
      my $props = $version->getProperties;

      # SMELL: which of these are standard, which are nice-to-haves by alfresco?
      foreach my $propId (qw(cmis:contentStreamFileName cmis:name
        cmis:baseTypeId cmis:isImmutable cmis:isLatestMajorVersion cmis:changeToken
        cmis:isVersionSeriesCheckedOut cmis:objectTypeId cmis:createdBy
        cmis:versionSeriesId cmis:versionSeriesCheckedOutBy cmis:lastModificationDate
        cmis:versionSeriesCheckedOutId cmis:isLatestVersion cmis:objectId
        cmis:checkinComment cmis:versionLabel cmis:creationDate cmis:contentStreamId
        cmis:contentStreamLength cmis:contentStreamMimeType cmis:lastModifiedBy
        cmis:isMajorVersion)) {
        note("   $propId=".($props->{$propId}->getValue||''));
        ok(defined $props->{$propId}) or diag("property $propId not defined");
      }
    }
  }
}

sub test_Document_checkOut_checkIn : Test(6) {
  my $this = shift;

  my $repo = $this->getRepository;

  my $obj = $this->getTestDocument;
  my $isCheckedOut = $obj->isCheckedOut;
  note("isCheckedout=$isCheckedOut");
  is($isCheckedOut, 0) or diag("test document is checked out");

  $obj->checkOut;
  $isCheckedOut = $obj->isCheckedOut;
  note("isCheckedout=$isCheckedOut");
  ok(defined $isCheckedOut) or diag("test document is NOT checked out");

  my $checkedOutBy = $obj->getCheckedOutBy;
  note("checkedOutBy=$checkedOutBy");
  ok(defined $checkedOutBy) or diag("no information checked out by");

  my $pwc = $obj->getPrivateWorkingCopy;
  ok(defined $pwc) or diag("can't get private working copy");
  note("pwc=".$pwc->getId);

  note("obj=".$obj->getId.", pwc=".$pwc->getId);
  isnt($obj->getId, $pwc->getId) or diag("document id should be different from pwc id");

  note("checking in");
  $pwc->checkIn("this is a test checkin time=".time, major=>1);
  note("pwc=".$pwc->getId);

  $pwc = $obj->getPrivateWorkingCopy;
  ok(!defined $pwc) or diag("there shouldn't be a private working copy anymore as the document has been checked in");
}

sub test_Document_getContentStream : Test(2) {
  my $this = shift;

  my $obj = $this->getTestDocument;

  my $content = $obj->getContentStream;
  ok(defined $content);

  my $name = $obj->getName;
  ok(defined $name);
  note("name=$name");
  _saveFile("/tmp/downloaded_$name", $content);
}

sub test_Document_setContentStream : Test(7) {
  my $this = shift;

  my $obj = $this->getTestDocument;
  my $id = $obj->getId;

  my $versionLabel = $obj->getProperty("cmis:versionLabel");
  ok(defined $versionLabel);
  note("versionLabel=$versionLabel");
  
  my $testFile = $this->{config}{testFile};
  my $updatedObj = $obj->setContentStream(
    contentFile => $testFile
  );
  ok(defined $updatedObj);
  ok($updatedObj->{xmlDoc});
  #print STDERR "xmlDoc=".$updatedObj->{xmlDoc}->toString(1)."\n";

  my $updatedId = $updatedObj->getId;
  note("before id=$id, after id=$updatedId");

  my $contentStreamMimeType = $updatedObj->getProperty("cmis:contentStreamMimeType");
  note("contentStreamMimeType=$contentStreamMimeType");
  is($contentStreamMimeType, "image/jpeg");

  my $updatedVersionLabel = $obj->getProperty("cmis:versionLabel");
  note("updatedVersionLabel=$updatedVersionLabel");
  ok(defined $updatedVersionLabel);
  ok($versionLabel ne $updatedVersionLabel);

  my $latestObj = $obj->getLatestVersion;
  my $latestVersionLabel = $latestObj->getProperty("cmis:versionLabel");
  is($updatedVersionLabel, $latestVersionLabel);
}

sub test_Document_getContentLink : Test {
  my $this = shift;

  my $obj = $this->getTestDocument;
  my $contentLink = $obj->getContentLink;
  note("content-link=$contentLink");
  ok(defined $contentLink) or diag("can't get content link for test file");
}

sub test_Document_getLatestVersion : Test(7) {
  my $this = shift;
  my $repo = $this->getRepository;

  $this->deleteTestDocument;
  my $doc = $this->getTestDocument;
  my $versionLabel = $doc->getProperty("cmis:versionLabel");
  note("versionLabel=$versionLabel");
  is("1.0", $versionLabel);

  my $beforeCheckedOutDocs = $repo->getCheckedOutDocs->getSize;
  note("beforeCheckedOutDocs=$beforeCheckedOutDocs");

  $doc->checkOut;

  is($repo->getCheckedOutDocs->getSize, $beforeCheckedOutDocs+1) or diag("checked out queue should be increasing");

  $doc->checkIn("this is a major checkin time=".time);
  is($repo->getCheckedOutDocs->getSize, $beforeCheckedOutDocs) or diag("checked out queue the same as before");

  $doc = $doc->getLatestVersion;
  $versionLabel = $doc->getProperty("cmis:versionLabel");
  note("latest versionLabel=$versionLabel");
  is("2.0", $versionLabel);

  $doc->checkOut;
  $doc->checkIn("this is a minor test checkin time=".time, major=>0);

  $doc = $doc->getLatestVersion;
  $versionLabel = $doc->getProperty("cmis:versionLabel");
  note("latest versionLabel=$versionLabel");
  is("2.1", $versionLabel);

  $doc = $doc->getLatestVersion(major=>1);
  $versionLabel = $doc->getProperty("cmis:versionLabel");
  note("latest major versionLabel=$versionLabel");
  is("2.0", $versionLabel);

  is($repo->getCheckedOutDocs->getSize, $beforeCheckedOutDocs) or diag("checked out queue the same as before");
}

sub test_Document_moveTo : Test(4) {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $this->getTestDocument;

  my ($parent1) = _getParents($obj);
  my $path = $parent1->getPath."/".$obj->getName;
  note("old path=".$path);
  note("parents: ".join(", ", map($_->getName, _getParents($obj))));

  my $targetFolder = $this->getTestFolder("2");
  my $newPath = $targetFolder->getPath."/".$obj->getName;
  note("new path=$newPath");

  $obj->moveTo($targetFolder);

  my ($parent2) = _getParents($obj);
  note("parents: ".join(", ", map($_->getName, _getParents($obj))));

  is(1, scalar(_getParents($obj))) or diag("not the same number of parents");
  isnt($parent1->getId, $parent2->getId) or diag("should have changed folder");

  my $result = $repo->getObjectByPath($path);
  ok(!defined $result) or diag("document should NOT be located in source folder anymore");

  $result = $repo->getObjectByPath($newPath);
  ok(defined $result) or diag("document should be located in target folder");
}

sub test_Document_move : Test(4) {
  my $this = shift;
  my $repo = $this->getRepository;

  my $obj = $this->getTestDocument;
  my $name = $obj->getName;

  my $targetFolder = $this->getTestFolder("2");
  my $targetPath = $targetFolder->getPath."/".$name;

  my ($sourceFolder) = _getParents($obj);
  my $sourcePath = $sourceFolder->getPath."/".$name;

  note("targetPath=$targetPath, sourcePath=$sourcePath");

  $obj->move(undef, $targetFolder);

  #this should be multifiled now, that is have multiple parents; yet it doesn't 
  note("parents: ".join(", ", map($_->getName, _getParents($obj))));

  #find the document at two paths now
  my $test = $repo->getObjectByPath($targetPath);
  ok(defined $test) or diag("document not found at target location");

  $test = $repo->getObjectByPath($sourcePath);
  ok(defined $test) or diag("document not found at source location");

  # delete it once should remove it twice
  $this->deleteTestDocument;

  $test = $repo->getObjectByPath($targetPath);
  ok(!defined $test) or diag("document should not be found at target location");

  $test = $repo->getObjectByPath($targetPath);
  ok(!defined $test) or diag("document should not be found at source location");
}

sub test_Document_unfile : Tests {
  my $this = shift;
  my $repo = $this->getRepository;

  my $exceptionOk = 0;
  my $obj = $this->getTestDocument;
  my $error;

  try {
    $obj->unfile;
  } catch WebService::Cmis::NotSupportedException with {
    $error = shift;
    is($error, "This repository does not support unfiling");
    $exceptionOk = 1;
  };
  return $error if $exceptionOk;

  my $unfiledDocs = $repo->getUnfiledDocs;
  ok(defined $unfiledDocs) or diag("can't get unfiled docs");

  note("found ".$unfiledDocs->getSize." unfiled document(s)");

  while(my $obj = $unfiledDocs->getNext) {
    note("name=".$obj->getName.", id=".$obj->getId.", url=".$obj->getSelfLink);
    isa_ok($obj, 'WebService::Cmis::Document');
  }
}

sub test_Document_getRenditions : Tests {
  my $this = shift;

  my $obj = $this->getTestDocument;

  my $renditions = $obj->getRenditions;
  ok(defined $renditions);
  note("renditions:");
  foreach my $rendition (values %$renditions) {
    ok(defined $rendition);
    note("rendition properties:".join(", ", sort keys %$rendition));
    ok(defined $rendition->{streamId});
    ok(defined $rendition->{mimetype});
    ok(defined $rendition->{kind});
    my @info = ();
    foreach my $key (keys %$rendition) {
      push @info, "   $key=$rendition->{$key}";
    }
    note(join("\n", @info));
  }
}

sub test_Document_getRenditionLink : Test(5) {
  my $this = shift;

  my $obj = $this->getTestDocument;
  my $link = $obj->getRenditionLink(kind=>"thumbnail");
  #the server might delay thumbnail creation beyond this test
  #ok(defined $link);
  #note("thumbnail=$link");

  $link = $obj->getRenditionLink(mimetype=>"Image");
  ok(defined $link);
  note("image=$link");

  $link = $obj->getRenditionLink(mimetype=>"Image", width=>16);
  ok(defined $link);
  note("image,16=$link");

  $link = $obj->getRenditionLink(mimetype=>"Image", width=>32);
  ok(defined $link);
  note("image,32=$link");

  $link = $obj->getRenditionLink(kind=>"icon", height=>16);
  ok(defined $link);
  note("icon=$link");

  $link = $obj->getRenditionLink(kind=>"icon", height=>11234020);
  ok(!defined $link);
}

sub test_Document_checkOut_cancelCheckOut : Test(8) {
  # SMELL: skip some when there is no support for pwc

  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $this->getTestDocument;

  my $id1 = $obj->getId;
  note("id1=$id1");

  my $pwc = $obj->getPrivateWorkingCopy;
  ok(!defined $pwc) or diag("oops, we didn't check it out yet, so there shouldn't be a pwc yet");

  $obj->checkOut;
  my $id2 = $obj->getId;
  note("id2=$id2");
  is($id1, $id2);
  ok($repo->getObject($id1));

  $pwc = $obj->getPrivateWorkingCopy;
  ok(defined $pwc) or diag("oops, where's my pwc");
  my $id3 = $obj->getId;
  note("id3=$id3");
  is($id1, $id3);

  my $pwcId = $pwc->getId;
  note("pwcId=".$pwcId);
  isnt($obj->getId, $pwc->getId) or diag("document id should be different from pwc id");

  $obj->cancelCheckOut;
  my $id4 = $obj->getId;
  note("id4=".$id4);
  ok($repo->getObject($id1));
  ok(!defined $repo->getObject($pwcId)) or diag("pwc should been gone by now");
}



1;

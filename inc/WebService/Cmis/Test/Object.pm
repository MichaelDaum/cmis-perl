package WebService::Cmis::Test::Object;
use base qw(WebService::Cmis::Test);
use Test::More;

use strict;
use warnings;

use WebService::Cmis qw(:collections :utils :relations :namespaces :contenttypes);
use WebService::Cmis::ACE;
use Error qw(:try);

sub test_Object_getProperties : Tests {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  my $props = $obj->getProperties;
  note("props:\n".join("\n", map("  ".$_->toString, values %$props)));

  ok(defined $props->{"cmis:baseTypeId"}) or diag("no baseTypeId found");
  ok(defined $props->{"cmis:objectId"}) or diag("no objectId found");
  ok(defined $props->{"cmis:name"}) or diag("no name found");

  foreach my $key (sort keys %$props) {
    my $val = $props->{$key}->getValue || '';
    ok(defined $val);
    note("$key = $val");
  }
}

sub test_Object_getProperty : Test {
  my $this = shift;

  require WebService::Cmis::Object;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;
  my $props = $obj->getProperties;
  my $name = $obj->getProperty("cmis:name");
  note("name=$name");
  is($name, $props->{"cmis:name"}->getValue);
}

sub test_Object_getPropertiesFiltered : Test(8) {
  my $this = shift;

  require WebService::Cmis::Object;
  my $repo = $this->getRepository;

  # SMELL: the root folder doesn't have a creator for some repos

  my $obj = $repo->getRootFolder;
  ok(defined $obj) or diag("no root folder found");

  ##### 1rst call
  my $props1 = $obj->getProperties("lastModifiedBy");
  note("found ".scalar(keys %$props1)." property");

  is(1, scalar(keys %$props1));

  my $prop1 = $props1->{"cmis:lastModifiedBy"}->getValue;
  ok(defined $prop1);

  ##### 2nd call
  my $props2 = $obj->getProperties("cmis:objectTypeId");
  note("found ".scalar(keys %$props2)." property");

  is(1, scalar(keys %$props2));

  my $prop2 = $props2->{"cmis:objectTypeId"}->getValue;
  ok(defined $prop2);

  ##### 3nd call
  my $props3 = $obj->getProperties("cmis:createdBy, cmis:creationDate");
  note("found ".scalar(keys %$props3)." property");
  note("props3=".join(', ', keys %$props3));

  is(2, scalar(keys %$props3));

  # SMELL: fails on nuxeo
  my $prop3 = $props3->{"cmis:createdBy"}->getValue;
  note("prop3=$prop3");
  ok(defined $prop3);

  # SMELL: fails on nuxeo
  my $prop4 = $props3->{"cmis:creationDate"}->getValue;
  ok(defined $prop4);

}

sub test_Object_getParents_root : Test(4) {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;
  ok($root) or diag("no root folder found");
  my $error;

  my $parents;
  try {
    $parents = $root->getObjectParents;
  } catch WebService::Cmis::NotSupportedException with {
    $error = shift;
    isa_ok($error, "WebService::Cmis::NotSupportedException");
    like($error, qr'^object does not support getObjectParents');
  };

  ok(!defined $parents) or diag("root doesn't have a parent");
}

sub test_Object_getParents_children : Tests {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;
  ok(defined $root) or diag("no root folder found");
  note("root=".$root->getId);

  my $children = $root->getChildren;
  note("found ".$children->getSize." children in root folder");

  while (my $obj = $children->getNext) {
    my $parents = $obj->getObjectParents;
    ok(defined $parents);

    my $parent;
    if ($parents->isa("WebService::Cmis::AtomFeed")) {
      is(1, $parents->getSize);
      $parent = $parents->getNext;
    } else {
      $parent = $parents;
    }

    note("object=".$obj->getName);
    note("parent=".$parent->getId);

    is($root->getId, $parent->getId) or diag("child doesn't point back to its parent");
  }
}

sub test_Object_getParents_subchildren : Tests {
  my $this = shift;
  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;

  ok($root) or diag("no root folder found");

  my $children = $root->getChildren;
  note("found ".$children->getSize." children in root folder");

  # get first folder
  my $folder;
  while(my $obj = $children->getNext) {
    if ($obj->getTypeId eq 'cmis:folder') {
      $folder = $obj;
      last;
    }
  }
  return unless $folder;

  $children = $folder->getChildren;
  note("found ".$children->getSize." children in sub folder ".$folder->getId.", url=".$folder->getSelfLink);

  while(my $obj = $children->getNext) {
    my $parents = $obj->getObjectParents;
    note("obj=$obj, name=".$obj->getName);
    note("parents=$parents, ref=".ref($parents));
    my $parent;
    if ($parents->isa("WebService::Cmis::AtomFeed")) {
      is(1, $parents->getSize);
      $parent = $parents->getNext;
    } else {
      $parent = $parents;
    }
    isa_ok($parent, "WebService::Cmis::Object");
  }
}

sub test_Object_getAppliedPolicies : Tests {
  my $this = shift;

  my $repo = $this->getRepository;
  my $rootCollection = $repo->getCollection(ROOT_COLL);
  ok(defined $rootCollection) or diag("can't fetch root collection");

  while(my $child = $rootCollection->getNext) {
    my $policies;
    my $exceptionOkay = 0;
    
    try {
      $policies = $child->getAppliedPolicies;
    } catch WebService::Cmis::NotSupportedException with {
      my $error = shift;
      is($error, 'This object has canGetAppliedPolicies set to false');
      $exceptionOkay = 1;
    };
    next if $exceptionOkay;

    ok(defined $policies);
    note("found ".$policies->getSize." policies for".$child->getName);
    while(my $obj = $policies->getNext) {
      isa_ok($obj, 'WebServices::Cmis::Policy');
      note("obj=".$obj->getName);
    }
  }
}

# SMELL: fails on nuxeo
sub test_Object_getRelations : Tests {
  my $this = shift;

  my $repo = $this->getRepository;
  my $rootCollection = $repo->getCollection(ROOT_COLL);
  ok(defined $rootCollection) or diag("can't fetch root collection");

  while(my $child = $rootCollection->getNext) {
    my $rels = $child->getRelationships;
    ok(defined $rels);
    note("found ".$rels->getSize." relations for".$child->getName);
    while(my $obj = $rels->getNext) {
      isa_ok($obj, 'WebServices::Cmis::Policy');
      note("obj=".$obj->getName);
    }
  }
}

sub test_Object_getTestFolder : Test {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $this->getTestFolder;
  ok($obj);
}

sub test_Object_getTestDocument : Test {
  my $this = shift;

  my $obj = $this->getTestDocument;
  ok(defined $obj);
}

sub test_Object_getAllowableActions : Tests {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $this->getTestDocument;

  my $allowableActions = $obj->getAllowableActions;
  ok(defined $allowableActions) or diag("can't get allowable actions");
  foreach my $action (sort keys %$allowableActions) {
    note("$action=$allowableActions->{$action}");
    like($action, qr'^can');
    like($allowableActions->{$action}, qr'^(0|1)$');
  }
}

sub test_Object_getObject : Test {
  my $this = shift;

  require WebService::Cmis::Object;

  my $repo = $this->getRepository;

  my $rootFolderId = $repo->getRepositoryInfo->{'rootFolderId'};
  my $obj = new WebService::Cmis::Object(repository=>$repo, id => $rootFolderId);

  ok(defined $obj) or diag("can't create an Object");
  note("obj=$obj");
}


sub test_Object_getName : Test(2) {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  my $props = $obj->getProperties;
  my $name = $props->{"cmis:name"}->getValue;
  ok(defined $name);
  note("cmis:name=$name");
  is($name, $obj->getProperty("cmis:name"));
}

sub test_Object_getSummary : Test {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;

  my $summary = $root->getSummary;
  ok(defined $summary);
  note("summary=$summary");
}

sub test_Object_getPublished : Test(2) {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;

  my $published = $root->getPublished;
  ok(defined $published);
  like($published, qr'^\d+');

  
  #require WebService::Cmis::Property;
  note("published=".WebService::Cmis::Property::formatDateTime($published)." ($published)");
}


sub test_Object_getTitle : Test {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;

  my $title = $root->getTitle;
  ok(defined $title);
  note("title=$title");
}


sub test_Object_getLinkFirst : Test(2) {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  my $href = $obj->getLink('*');
  ok(defined $href);
  note("href=$href");

  $href =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port
  like($href, qr"^$this->{config}{url}");
}

sub test_Object_getLink : Test(2) {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  my $href = $obj->getLink(ACL_REL);
  note("href=$href");
  ok(defined $href);

  $href =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port
  like($href, qr"^$this->{config}{url}.*acl");
}

sub test_Object_getLinkFiltered : Test(2) {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  my $href = $obj->getLink(DOWN_REL, ATOM_XML_FEED_TYPE_P);
  ok(defined $href);

  $href =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port
  like($href, qr"^$this->{config}{url}.*children");

}

sub test_Object_getSelfLink : Test(2) {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  my $href = $obj->getSelfLink;
  ok(defined $href);

  $href =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port
  like($href, qr/^$this->{config}{url}/);
}

sub test_Object_getACL : Test(2) {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $this->getTestFolder;

  my $acl;
  my $exceptionOk = 0;
  my $error;

  try {
    $acl = $obj->getACL;
  } catch WebService::Cmis::NotSupportedException with {
    my $error = shift;
    like($error, "This repository does not support ACLs");
    $exceptionOk = 1;
  };
  return $error if $exceptionOk;

  ok(defined $acl);

  note($acl->{xmlDoc}->toString);
  my $result = $acl->toString;
  ok(defined $result);

  # SMELL: add some tests that make sense
}

# SMELL: xCmis doesn't support filtering by type
sub test_Object_getFolderParent : Test(4) {
  my $this = shift;
  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;

  my $rootParent = $root->getFolderParent;
  ok(!defined $rootParent);

  my $subfolder = $root->getChildren(types=>"folders")->getNext;
  ok(defined $subfolder);
  isa_ok($subfolder, "WebService::Cmis::Folder");
  
  my $parent = $subfolder->getFolderParent;
  is($root->getId, $parent->getId);
  note("parent=".$parent->getId);
}

sub test_Object_updateProperties : Test(3) {
  my $this = shift;

  my $obj = $this->getTestDocument;

  my $name1 = $obj->getName;
  my $summary1 = $obj->getSummary;
  my $title1 = $obj->getTitle;
  my $updated1 = $obj->getUpdated;

  note("name=$name1, title=$title1, summary=$summary1, updated=$updated1, url=".$obj->getSelfLink);

  my $extension = $name1;
  $extension =~ s/^.*\.(.*?)$/$1/;

  my $newName = 'SomeOtherName.'.$extension;

  sleep(1);

  $obj->updateProperties([
    WebService::Cmis::Property::newString(
      id => 'cmis:name',
      value => $newName,
    ),
  ]);

  my $name2 = $obj->getName;
  my $summary2 = $obj->getSummary;
  my $title2 = $obj->getTitle;
  my $updated2 = $obj->getUpdated;

  note("name=$name2, title=$title2, summary=$summary2 updated=$updated2");

  is($newName, $name2);
  isnt($name1, $name2);
  isnt($updated1, $updated2);
}

sub test_Object_updateSummary : Test(4) {
  my $this = shift;

  my $obj = $this->getTestDocument;

  my $name1 = $obj->getName;
  my $summary1 = $obj->getSummary;
  my $title1 = $obj->getTitle;
  my $updated1 = $obj->getUpdated;

  note("name=$name1, title=$title1, summary=$summary1, updated=$updated1, url=".$obj->getSelfLink);

  sleep(1);

  my $text = 'icon showing a red button written "free" on it';
  $obj->updateSummary($text);

  my $name2 = $obj->getName;
  my $summary2 = $obj->getSummary;
  my $title2 = $obj->getTitle;
  my $updated2 = $obj->getUpdated;

  note("name=$name2, title=$title2, summary=$summary2 updated=$updated2");

  is($name1, $name2);
  is($text, $summary2);
  isnt($updated1, $updated2);
  isnt($summary1, $summary2);
}

sub test_Object_updateSummary_empty : Test(2) {
  my $this = shift;

  my $obj = $this->getTestDocument;

  my $summary = $obj->getSummary;
  note("summary=$summary");
  ok($summary);

  my $text = '';
  $obj->updateSummary($text);
  $summary = $obj->getSummary;
  is($summary, '');
}

sub test_Object_applyACL : Test(11) {
  my $this = shift;

  my $obj = $this->getTestFolder;

  my $acl = $obj->getACL;
  ok(defined $acl);
  my $origSize = $acl->getSize;
  note("1: our ACL has got $origSize ACEs");
  #note("1: acl=".$acl->toString);

  my $ace = new WebService::Cmis::ACE(principalId => 'jdoe', permissions => 'cmis:write', direct => 'true');
  $acl->addEntry($ace);

  note("2: after adding one ACE we have ".($origSize+1)." ACEs");
  #note("2: acl=".$acl->toString);
  is($acl->getSize, $origSize+1);

  my $returnAcl = $obj->applyACL($acl);
  my $returnSize = $returnAcl->getSize;
  ok(defined $returnAcl);
  note("3: applying the ACL we get $returnSize ACEs in return ... could be more than one on plus.");
  #note("3: acl=".$returnAcl->toString);
  ok($returnSize >= $origSize+1);

  my $againAcl = $obj->getACL;
  my $againSize = $againAcl->getSize;
  note("4: getting a fresh ACL from the object has got $againSize ACEs.");
  ok(defined $againAcl);
  is($againSize, $returnSize);
  is($againAcl->toString, $returnAcl->toString);

  $againAcl->removeEntry("jdoe");
  $againSize = $againAcl->getSize;
  note("5: removing all ACEs for jdoe leaves us with $againSize");
  is($againSize, $origSize);

  $returnAcl = $obj->applyACL($againAcl);
  $returnSize = $returnAcl->getSize;
  ok(defined $returnAcl);
  is($returnSize, $againSize);
  is($returnAcl->toString, $againAcl->toString);
}

sub test_Object_applyACL_same : Tests {
  my $this = shift;

  my $obj = $this->getTestFolder;
  my $acl = $obj->getACL;

  ok(defined $acl);
  my $origSize = $acl->getSize;
  note("1: our ACL has got $origSize ACEs");
  ok($origSize > 0);
  #note("1: acl=".$acl->toString);

  $acl->addEntry(new WebService::Cmis::ACE(
    principalId => 'jdoe', 
    permissions => 'cmis:write', 
    direct => 'true'
  ));
  my $size = $acl->getSize;
  note("2: our ACL has got $size ACEs now");
  is($size, $origSize+1);
  #note("2: acl=".$acl->toString);

  # adding the same again
  $acl->addEntry(new WebService::Cmis::ACE(
    principalId => 'jdoe', 
    permissions => 'cmis:write', 
    direct => 'true'
  ));
  $size = $acl->getSize;
  note("3: our ACL has got $size ACEs now");
  is($size, $origSize+2);

  # adding the same again
  $acl->addEntry(new WebService::Cmis::ACE(
    principalId => 'jdoe', 
    permissions => 'cmis:write', 
    direct => 'true'
  ));
  $size = $acl->getSize;
  note("4: our ACL has got $size ACEs now");
  is($size, $origSize+3);

  note("before acl=".$acl->toString);

  my $returnAcl = $obj->applyACL($acl);
  my $returnSize = $returnAcl->getSize;
  note("4: the returned ACL has got $returnSize ACEs");
  ok($returnSize < $size);
  note("after acl=".$returnAcl->toString);
  note($returnAcl->getXmlDoc->toString(1));
}

1;

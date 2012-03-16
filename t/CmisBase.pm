# Base tests for Cmis tests
package CmisBase;

use strict;
use warnings;
binmode(STDERR, ":utf8");
binmode(STDOUT, ":utf8");

use Unit::TestCase;
use WebService::Cmis qw(:collections :utils :relations :namespaces :contenttypes);
use XML::LibXML qw(:libxml);
use Exporter qw(import);
use Cache::FileCache ();
use File::Temp ();
use Error qw(:try);
use WebService::Cmis::ClientException;
use WebService::Cmis::NotSupportedException;

our @ISA = qw( Exporter Unit::TestCase );
our @EXPORT;

foreach my $symbol (keys %CmisBase::) {
  next unless $symbol =~ /^test_/;
  push @EXPORT, $symbol;
  #print "exporting $symbol\n";
}

sub new {
  my $class = shift;
  my $connection = shift;
  my $this = $class->SUPER::new(@_);

  die "ERROR: no connection" unless defined $connection;
  die "ERROR: no url in connection" unless defined $connection->{url};
  #print STDERR "connection=$connection->{url}\n";
  
  $this->{connection} = $connection;
  return $this;
}

sub DESTROY {
  my $this = shift;

  #print STDERR "DESTROY\n";

  foreach my $key (keys %{$this->{testDocuments}}) {
    $this->deleteTestDocument($key);;
  }

  foreach my $key (keys %{$this->{testFolders}}) {
    $this->deleteTestFolder($key);;
  }
}

sub saveFile {
  my ($name, $text) = @_;
  my $FILE;
  unless (open($FILE, '>', $name)) {
    die "Can't create file $name - $!\n";
  }
  print $FILE $text;
  close($FILE);
}

sub getClient {
  my $this = shift;

  unless (defined $this->{client}) {
    my $tempDir = File::Temp::tempdir(CLEANUP => 1);
    #print STDERR "temporary cache in $tempDir\n";
    my $cache = Cache::FileCache->new({
      cache_root => $tempDir
      }
    );
    $this->{client} = WebService::Cmis::getClient(
      %{$this->{connection}},
      #cache => $cache
    );
  }

  return $this->{client};
}

sub getRepository {
  return $_[0]->getClient->getRepository;
}

sub getTestFolderName {
  my $this = shift;
  my $key = shift;

  $key ||= 'default';
  $this->{testFolderNames} = {} unless defined $this->{testFolderNames};

  unless (defined $this->{testFolderNames}{$key}) {
    $this->{testFolderNames}{$key} = "WebService_Cmis_TestFolder_".$key."_".time;
  }

  return $this->{testFolderNames}{$key};
}

sub deleteTestFolder {
  my $this = shift;
  my $key = shift;

  $key ||= 'default';
  $this->{testFolders} = {} unless defined $this->{testFolders};

  #print STDERR "called deleteTestFolder\n";


  if (defined $this->{testFolders}{$key}) {
    $this->{testFolders}{$key}->delete;
  }

  delete $this->{testFolders}{$key};
}

sub getTestFolder {
  my $this = shift;
  my $key = shift;

  $key ||= 'default';
  $this->{testFolders} = {} unless defined $this->{testFolders};

  unless (defined $this->{testFolders}{$key}) {
    my $name = $this->getTestFolderName($key);
    #print STDERR "creating a test folder $name\n";
    $this->assert_matches('^WebService_Cmis_.*$', $name);

    my $repo = $this->getRepository;
    my $root = $repo->getRootFolder;

    #print STDERR "creating folder /$name\n";
    $this->{testFolders}{$key} = $root->createFolder($name, summary=>"this is a test folder used by WebService::Cmis' testsuite");
    if ($this->{testFolders}{$key}->getId eq $root->getId) {
      print STDERR "ERROR: don't use root as test folder\n\n";
      exit; #emergency
    }

    $this->assert_not_null($this->{testFolders}{$key}, "ERROR: can't create test folder $name\n\n");
  }

  return $this->{testFolders}{$key};
}

sub deleteTestDocument {
  my $this = shift;
  my $key = shift;

  $key ||= 'default';
  $this->{testDocuments} = {} unless defined $this->{testDocuments};

  try {
    if (defined $this->{testDocuments}{$key}) {
      #print STDERR "deleting test document\n";
      my $pwc = $this->{testDocuments}{$key}->getPrivateWorkingCopy;
      $pwc->cancelCheckOut if $pwc;
      $this->{testDocuments}{$key}->delete;
      delete $this->{testDocuments}{$key};
    }
  } catch WebService::Cmis::ClientException with {
    my $error = shift;
    #print STDERR "ERROR in deleteTestDocument: $error\n";
    # ignore
  };
}

sub getTestDocument {
  my $this = shift;
  my $key = shift;

  $key ||= 'default';

  #print STDERR "called getTestDocument($key)\n";
  $this->{testDocuments} = {} unless defined $this->{testDocuments};

  unless (defined $this->{testDocuments}{$key}) {
    my $folder = $this->getTestFolder($key);
    my $repo = $this->getRepository;

    my $testFile = "./CmisPlugin/data/free.jpg";
    $this->assert(-e $testFile, "ERROR: testFile=$testFile not found\n\n");

    # first delete it if it exists
    my $path = "/".$this->getTestFolderName($key)."/free.jpg";
    #print STDERR "path=$path\n";

    my $document = $repo->getObjectByPath($path);
    return $document if defined $document;

    #print STDERR "uploading $testFile to $path\n";
    $document = $folder->createDocument(
      "free.jpg",
      contentFile=>$testFile
    );
 
    $this->assert_not_null($document, "ERROR: can't upload document\n\n");

    $this->{testDocuments}{$key} = $document;
  }

  return $this->{testDocuments}{$key};
}

sub test_getClient {
  my $this = shift;

  my $client = WebService::Cmis::getClient;
  $this->assert_str_equals( "CMIS client connection to ", $client->toString );
}

sub test_getClient_2 {
  my $this = shift;

  my $client = $this->getClient;
  my $url = $this->{connection}{url};

  $this->assert_str_equals( "CMIS client connection to $url", $client->toString );
}

sub test_repository_ClientException_404 {
  my $this = shift;

  my $client = $this->getClient;

  my $doc;
  try {
    $doc = $client->get("fooBar");
  } catch WebService::Cmis::ClientException with {
    my $error = shift;
    $this->assert(ref($error));
    $this->assert_str_equals("WebService::Cmis::ClientException", ref($error));
    $this->assert_matches("^404 Not Found", $error);
  };

  $this->assert_null($doc);
}

sub test_repository_ClientException_401 {
  my $this = shift;

  my $badClient = WebService::Cmis::getClient(
    %{$this->{connection}},
    user => "foo",
    password => "bar",
  );

  my $result;
  try {
    $result = $badClient->get;
  } catch WebService::Cmis::ClientException with {
    my $error = shift;
    $this->assert(ref($error));
    $this->assert_str_equals("WebService::Cmis::ClientException", ref($error));
    $this->assert_matches("^401 Unauthorized", $error);
  };

  $this->assert_null($result);
}

sub test_repository_ServerExceptio_500 {
  my $this = shift;

  my $badClient = WebService::Cmis::getClient(
    url => "http://doesnotexist.local.foobar:8080/alfresco/service/cmis",
    user => "foo",
    password => "bar",
  );

  my $result;
  try {
    $result = $badClient->get;
  } catch WebService::Cmis::ServerException with {
    my $error = shift;
    $this->assert(ref($error));
    $this->assert_str_equals("WebService::Cmis::ServerException", ref($error));
    #print STDERR "error=$error\n";
    $this->assert_matches("^500 Can't connect", $error);
  };

  $this->assert_null($result);

}

sub test_repository_raw {
  my $this = shift;

  my $client = $this->getClient;
  my $doc = $client->get;
  $this->assert_matches('^<\?xml version="1.0"( encoding="(utf|UTF)-8")?\?>.*', $doc->toString);
}

sub test_Client_getRepositories {
  my $this = shift;

  my $client = $this->getClient;
  my $repositories = $client->getRepositories;

  my $nrRepos = scalar(keys %$repositories);
  #print STDERR "found $nrRepos repository(ies)\n";
  $this->assert(scalar($nrRepos) > 0, "ERROR: can't find at least one repository\n\n");

 foreach my $repo (values %$repositories) {
   my $info = $repo->getRepositoryInfo;

   # SMELL: what's the absolute minimum?
   foreach my $key qw(repositoryName repositoryId) {
     #print STDERR "$key=$info->{$key}\n";
     $this->assert_not_null($info->{$key});
   }
 }
}

sub test_Client_getDefaultRepository {
  my $this = shift;

  my $repo = $this->getRepository;

  $this->assert_not_null($repo, "ERROR: can't find default repository\n\n");
  $this->assert_str_equals("WebService::Cmis::Repository", ref($repo));
}

sub test_Repository_getRepositoryName {
  my $this = shift;
  
  my $repo = $this->getRepository;
  my $name = $repo->getRepositoryName;

  #print STDERR "name=$name\n";
  $this->assert_not_null($name);
}

sub test_Repository_getRepositoryId {
  my $this = shift;
  
  my $repo = $this->getRepository;
  my $id1 = $repo->getRepositoryId;

  #print STDERR "id1=$id1\n";
  $this->assert_not_null($id1);

  my $repo2 = $this->getRepository($id1);
  my $id2 = $repo2->getRepositoryId;
  $this->assert_not_null($id2);
  #print STDERR "id2=$id2\n";

  $this->assert_str_equals($id1, $id2);
}

sub test_Repository_getRepository_unknown {
  my $this = shift;
  my $client = $this->getClient;
  my $repo = $client->getRepository("foobarbaz");
  $this->assert_null($repo);
}

sub test_Repository_getRepositoryInfo {
  my $this = shift;

  my $repo = $this->getRepository;

  my $info = $repo->getRepositoryInfo;

  $this->assert_null($info->{capabilities}, "ERROR: capabilities should not be listed in repository info\n\n");
  $this->assert_null($info->{aclCapability}, "ERROR: aclCapabilities should not be listed in repository info\n\n" );

  #print STDERR "repositoryInfo :\n".join("\n", map("  ".$_.'='.$info->{$_}, keys %$info))."\n";

  # include
  # SMELL: what's the absolute minimum?
  foreach my $key qw(repositoryName repositoryId) {
    #print STDERR "$key=$info->{$key}\n";
    $this->assert_not_null($info->{$key});
  }
}

sub test_Repository_getCapabilities {
  my $this = shift;

  my $repo = $this->getRepository;

  my $caps = $repo->getCapabilities;

  # no capabilities at all
  return unless scalar keys %$caps;

  #print STDERR "caps:\n".join("\n", map("  ".$_.'='.$caps->{$_}, keys %$caps))."\n";

  foreach my $key qw( Renditions Multifiling ContentStreamUpdatability Unfiling
    GetFolderTree AllVersionsSearchable Changes Join ACL Query PWCSearchable
    PWCUpdatable VersionSpecificFiling GetDescendants) {
    my $val = $caps->{$key};
    $this->assert_not_null($val, "ERROR: $key capability not found\n\n");
    $this->assert_matches('^(0|1)$', $val);
  }
}

sub test_Repository_getSupportedPermissions {
  my $this = shift;

  my $repo = $this->getRepository;
  my $perms;
  my $exceptionOk = 0;

  try {
    $perms = $repo->getSupportedPermissions;
  } catch WebService::Cmis::NotSupportedException with {
    my $error = shift;
    $this->assert_str_equals("This repository does not support ACLs", $error);
    $exceptionOk = 1;
  };
  return if $exceptionOk;

  #print STDERR "perms='$perms'\n";

  $this->assert_matches('^(basic|repository|both)$', $perms);
}

sub test_Repository_getPermissionDefinitions {
  my $this = shift;

  my $repo = $this->getRepository;

  my $permDefs;
  my $exceptionOk = 0;
  
  try {
    $permDefs = $repo->getPermissionDefinitions;
  } catch WebService::Cmis::NotSupportedException with {
    my $error = shift;
    $this->assert_str_equals("This repository does not support ACLs", $error);
    $exceptionOk = 1;
  };
  return if $exceptionOk;

  $this->assert_not_null($permDefs, "ERROR: no permission definitions found\n");

  my $foundCmisRead;
  my $foundCmisWrite;
  foreach my $key (keys %$permDefs) {
    #print STDERR "$key = $permDefs->{$key}\n";# if $key =~ /^cmis:/;
    $this->assert_matches('{http://|cmis:', $key);

    # SMELL: nuxeo calls the basic cmis permissions "basic"... oh well
    $foundCmisRead = 1 if $key =~ /cmis:(read|basic)/;
    $foundCmisWrite = 1 if $key =~ /cmis:(write|basic)/;
  }
  $this->assert_not_null($foundCmisRead, "ERROR: cmis:read not found in permission definition\n\n");
  $this->assert_not_null($foundCmisWrite, "ERROR: cmis:write not found in permission definition\n\n");
}

sub test_Repository_getPermissionMap {
  my $this = shift;

  my $repo = $this->getRepository;
  my $permMap;
  my $exceptionOk = 0;

  try {
    $permMap = $repo->getPermissionMap;
  } catch WebService::Cmis::NotSupportedException with {
    my $error = shift;
    $this->assert_str_equals("This repository does not support ACLs", $error);
    $exceptionOk = 1;
  };
  return if $exceptionOk;

  $this->assert_not_null($permMap, "ERRROR: no permission map found\n\n");

  #print STDERR "perms=".join(' ', keys %$permMap)."\n";
  foreach my $perm (keys %$permMap) {
    #print STDERR "To do this: $perm, you must have one of permissions ".join(', ', @{$permMap->{$perm}})."\n";
  }

  # SMELL: which of these are standard, which are nice to have?
  foreach my $perm qw(canSetContent.Document canDeleteTree.Folder
    canAddPolicy.Object canAddPolicy.Policy canGetChildren.Folder
    canGetAllVersions.VersionSeries canCancelCheckout.Document canApplyACL.Object
    canMove.Target canGetDescendents.Folder canRemovePolicy.Policy
    canCreateFolder.Folder canGetParents.Folder canGetFolderParent.Object
    canGetAppliedPolicies.Object canUpdateProperties.Object canMove.Object
    canDeleteContent.Document canCheckout.Document canDelete.Object
    canRemoveFromFolder.Object canCreateDocument.Folder canGetProperties.Object
    canAddToFolder.Folder canRemovePolicy.Object canCheckin.Document
    canAddToFolder.Object canGetACL.Object canViewContent.Object) {
    
    $this->assert_not_null($permMap->{$perm}, "ERROR: permission $perm not defined\n\n");
  }
}

sub test_Repository_getPropagation {
  my $this = shift;

  my $repo = $this->getRepository;
  my $prop;
  my $exceptionOk = 0;

  try {
    $prop = $repo->getPropagation;
  } catch WebService::Cmis::NotSupportedException with {
    my $error = shift;
    $this->assert_str_equals("This repository does not support ACLs", $error);
    $exceptionOk = 1;
  };
  return if $exceptionOk;

  #print STDERR "prop=$prop\n";
  $this->assert_matches('objectonly|propagate|repositorydetermined', $prop);
}

sub test_Repository_getRootFolderId {
  my $this = shift;

  my $repo = $this->getRepository;

  my $rootFolderId = $repo->getRepositoryInfo->{'rootFolderId'};

  #print STDERR "rootFolderId=$rootFolderId\n";

  $this->assert_not_null($rootFolderId, "ERROR: no rootFolder found\n\n");
}

sub test_Repository_getUriTemplates {
  my $this = shift;

  my $repo = $this->getRepository;

  my $uriTemplates = $repo->getUriTemplates;

  #print STDERR "types=".join(' ', keys %$uriTemplates)."\n";

  foreach my $type qw(objectbypath query objectbyid typebyid) {
    $this->assert_not_null($uriTemplates->{$type}, "ERROR: no uri template for $type\n\n"); 
    #print "type=$type, mediatype=$uriTemplates->{$type}{mediatype}, template=$uriTemplates->{$type}{template}\n";
  }
}

sub test_Repository_getUriTemplate {
  my $this = shift;

  my $repo = $this->getRepository;

  foreach my $type qw(objectbypath query objectbyid typebyid) {
    my $template = $repo->getUriTemplate($type);
    $this->assert_not_null($template, "ERROR: no uri template for $type\n\n"); 
  }
}

sub test_Repository_getCollectionLink {
  my $this = shift;

  my $repo = $this->getRepository;

  my $href = $this->{connection}{url};
  $href =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port

  # UNFILED_COLL not supported by all repositories; 
  # SMELL: test for unfiled capability
  foreach my $collectionType (QUERY_COLL, TYPES_COLL, CHECKED_OUT_COLL, ROOT_COLL) {
    my $link = $repo->getCollectionLink($collectionType);
    #print "type=$collectionType, link=".($link||'')."\n";
    $this->assert_not_null($link);
    $link =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port
    $this->assert_matches("^$href", $link);
  }
}

sub test_Repository_getCollection {
  my $this = shift;

  my $repo = $this->getRepository;

  # QUERY_COLL
  my $error;

  try {
    $repo->getCollection(QUERY_COLL);
  } catch Error::Simple with {
    $error = shift;
    $this->assert_matches('^query collection not supported', $error);
  };
  $this->assert_not_null($error);

  # TYPES_COLL
  my $typeDefs = $repo->getCollection(TYPES_COLL);
  $this->assert_str_equals('WebService::Cmis::AtomFeed::ObjectTypes', ref($typeDefs));
  while (my $typeDef = $typeDefs->getNext) {
    $this->assert_str_equals('WebService::Cmis::ObjectType', ref($typeDef));
    #print "typeDef=".$typeDef->toString."\n";
  }

  # other collections
  # SMELL: nuxeo throws a 405 on CHECKED_OUT
  foreach my $collectionType (CHECKED_OUT_COLL, UNFILED_COLL, ROOT_COLL) {
    my $result = $repo->getCollection($collectionType);
    #print STDERR "collectionType=$collectionType, result=$result, nrObjects=".$result->getSize."\n";
    $this->assert_not_null($result);
  }
}

sub test_Repository_getTypeDefinition {
  my $this = shift;

  my $repo = $this->getRepository;
  my $objectType = $repo->getTypeDefinition('cmis:folder');
  
  #print "id=".$objectType->getId.", displayName=".$objectType->getDisplayName.", description=".$objectType->getDescription.", link=".$objectType->getLink."\n";

  $this->assert_not_null($objectType->getId);
  $this->assert_not_null($objectType->getDisplayName);
  $this->assert_not_null($objectType->getQueryName);
  $this->assert_not_null($objectType->{xmlDoc});

  $this->assert_str_equals('cmis:folder', $objectType->toString);
}


sub test_ObjectType {
  my $this = shift;

  my $repo = $this->getRepository;

  my $typeDefs = $repo->getTypeDefinitions;
  $this->assert_str_equals('WebService::Cmis::AtomFeed::ObjectTypes', ref($typeDefs));

  while (my $objectType = $typeDefs->getNext) {
    $this->assert_str_equals('WebService::Cmis::ObjectType', ref($objectType));

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

    $this->assert_str_equals($id, $objectType->getId);
    $this->assert_str_equals($displayName, $objectType->getDisplayName);
    $this->assert_str_equals($description, $objectType->getDescription);
    $this->assert_str_equals($link, $objectType->getLink);
    $this->assert_str_equals($baseId, $objectType->getBaseId);
    $this->assert_str_equals($localName, $objectType->getLocalName);
    $this->assert_str_equals($localNamespace, $objectType->getLocalNamespace);
    $this->assert_str_equals($queryName, $objectType->getQueryName);
    $this->assert_str_equals($contentStreamAllowed, ($objectType->getContentStreamAllowed||''));

    $this->assert_str_equals($isCreatable, $objectType->isCreatable);
    $this->assert_str_equals($isFileable, $objectType->isFileable);
    $this->assert_str_equals($isQueryable, $objectType->isQueryable);
    $this->assert_str_equals($isFulltextIndexed, $objectType->isFulltextIndexed);
    $this->assert_str_equals($isIncludedInSupertypeQuery, $objectType->isIncludedInSupertypeQuery);
    $this->assert_str_equals($isControllablePolicy, $objectType->isControllablePolicy);
    $this->assert_str_equals($isControllableACL, $objectType->isControllableACL);
    $this->assert_str_equals($isVersionable, $objectType->isVersionable);
  }
}

sub test_PropertyType {
  my $this = shift;

  my $repo = $this->getRepository;

  my $typeDefs = $repo->getTypeDefinitions;
  $this->assert_str_equals('WebService::Cmis::AtomFeed::ObjectTypes', ref($typeDefs));

  while(my $objectType = $typeDefs->getNext) {

    # type attributes
    #print STDERR "### objectType=".$objectType->toString."\n";
    my $objAttrs = $objectType->getAttributes;
    $this->assert_not_null($objAttrs);

    foreach my $key (keys %$objAttrs) {
      #print STDERR "  * $key=$objAttrs->{$key}\n";
    }

    # type property definitions
    my $propDefs = $objectType->getPropertyDefinitions;
    $this->assert_not_null($propDefs);

    foreach my $propDef (values %$propDefs) {
      #print STDERR "|-> propDef=".$propDef->toString."\n";

      my $attrs = $propDef->getAttributes;
      $this->assert_not_null($attrs);
      foreach my $key (keys %$attrs) {
        #print STDERR "    $key=$attrs->{$key}\n";
      }
    }
  }
}

sub test_Cmis_collectionTypes {
  my $this = shift;

  $this->assert_equals(QUERY_COLL, "query");
  $this->assert_equals(TYPES_COLL, "types");
  $this->assert_equals(CHECKED_OUT_COLL, "checkedout");
  $this->assert_equals(UNFILED_COLL, "unfiled");
  $this->assert_equals(ROOT_COLL, "root");
}

sub test_PropertyBoolean_parse {
  my $this = shift;

  require WebService::Cmis::Property;
  $this->assert_num_equals(0, WebService::Cmis::Property::parseBoolean(''));
  $this->assert_num_equals(0, WebService::Cmis::Property::parseBoolean(' '));
  $this->assert_num_equals(1, WebService::Cmis::Property::parseBoolean('x'));
  $this->assert_num_equals(0, WebService::Cmis::Property::parseBoolean(0));
  $this->assert_num_equals(1, WebService::Cmis::Property::parseBoolean(1));
  $this->assert_num_equals(0, WebService::Cmis::Property::parseBoolean('0')); # argh
  $this->assert_num_equals(1, WebService::Cmis::Property::parseBoolean('1'));
  $this->assert_num_equals(1, WebService::Cmis::Property::parseBoolean('on'));
  $this->assert_num_equals(1, WebService::Cmis::Property::parseBoolean('ON'));
  $this->assert_num_equals(0, WebService::Cmis::Property::parseBoolean('off'));
  $this->assert_num_equals(0, WebService::Cmis::Property::parseBoolean('OFF'));
  $this->assert_num_equals(1, WebService::Cmis::Property::parseBoolean('true'));
  $this->assert_num_equals(1, WebService::Cmis::Property::parseBoolean('True'));
  $this->assert_num_equals(1, WebService::Cmis::Property::parseBoolean('TRUE'));
  $this->assert_num_equals(0, WebService::Cmis::Property::parseBoolean('false'));
  $this->assert_num_equals(0, WebService::Cmis::Property::parseBoolean('False'));
  $this->assert_num_equals(0, WebService::Cmis::Property::parseBoolean('False'));
  $this->assert_num_equals(1, WebService::Cmis::Property::parseBoolean('yes'));
  $this->assert_num_equals(0, WebService::Cmis::Property::parseBoolean('no'));
}

sub test_PropertyBoolean_unparse {
  my $this = shift;

  require WebService::Cmis::Property;

  $this->assert_str_equals('false', WebService::Cmis::Property::formatBoolean(0));
  $this->assert_str_equals('false', WebService::Cmis::Property::formatBoolean('0'));
  $this->assert_str_equals('true', WebService::Cmis::Property::formatBoolean('1'));
  $this->assert_str_equals('true', WebService::Cmis::Property::formatBoolean(1));
  $this->assert_str_equals('foobar', WebService::Cmis::Property::formatBoolean('foobar'));
  $this->assert_str_equals('none', WebService::Cmis::Property::formatBoolean());
}

sub test_PropertyId_parse {
  my $this = shift;

  require WebService::Cmis::Property;
  $this->assert_str_equals('123', WebService::Cmis::Property::parseId('123'));
  $this->assert_num_equals(123, WebService::Cmis::Property::parseId(123));
}

sub test_PropertyInteger_parse {
  my $this = shift;

  require WebService::Cmis::Property;
  $this->assert_num_equals(123, WebService::Cmis::Property::parseInteger(123));
  $this->assert_num_equals(123, WebService::Cmis::Property::parseInteger('123 '));
  $this->assert_num_equals(123, WebService::Cmis::Property::parseInteger(123));
  $this->assert_num_equals(123, WebService::Cmis::Property::parseInteger(123.456));
}

sub test_PropertyDecimal_parse {
  my $this = shift;

  require WebService::Cmis::Property;
  $this->assert_num_equals(123.456, WebService::Cmis::Property::parseDecimal(123.456, 'propertyDecimal'));
  $this->assert_num_equals(123.456, WebService::Cmis::Property::parseDecimal('123.456 foobar', 'propertyDecimal'));
}

sub test_Property_parseDateTime {
  my $this = shift;

  require WebService::Cmis::Property;

  $this->assert_num_equals(1295363154, WebService::Cmis::Property::parseDateTime('2011-01-18T15:05:54.951+01:00'));
  $this->assert_num_equals(1295363154, WebService::Cmis::Property::parseDateTime('foo 2011-01-18T15:05:54.951+01:00 bar'));
  $this->assert_null(WebService::Cmis::Property::DateTime->parse('foo'));
}

sub test_Property_parseDateTime_self {
  my $this = shift;

  require WebService::Cmis::Property;

  my $testDateString = "2011-01-25T13:22:28+01:00";
  my $epochSeconds = WebService::Cmis::Property::parseDateTime($testDateString);
  #print STDERR "epochSeconds=$epochSeconds\n";

  my $dateString = WebService::Cmis::Property::formatDateTime($epochSeconds);
  #print STDERR "dateString=$dateString\n";

  $this->assert_str_equals($testDateString, $dateString);
}

sub test_Property_formatDateTime {
  my $this = shift;

  require WebService::Cmis::Property;

  $this->assert_str_equals('2011-01-18T15:05:54+01:00', WebService::Cmis::Property::formatDateTime(1295363154));
  $this->assert_str_equals('none', WebService::Cmis::Property::formatDateTime('foo'));
  $this->assert_str_equals('1970-01-01T00:00:00+01:00', WebService::Cmis::Property::formatDateTime(0));
}

sub test_Object_getProperties {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  my $props = $obj->getProperties;
  #print STDERR "props:\n".join("\n", map("  ".$_->toString, values %$props))."\n";

  $this->assert_not_null($props->{"cmis:baseTypeId"}, "ERROR: no baseTypeId found\n\n");
  $this->assert_not_null($props->{"cmis:objectId"}, "ERROR: no objectId found\n\n");
  $this->assert_not_null($props->{"cmis:name"}, "ERROR: no name found\n\n");

  foreach my $key (sort keys %$props) {
    my $val = $props->{$key}->getValue || '';
    #print STDERR "$key = $val\n";
  }
}

sub test_Object_getProperty {
  my $this = shift;

  require WebService::Cmis::Object;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;
  my $props = $obj->getProperties;
  my $name = $obj->getProperty("cmis:name");
  #print STDERR "name=$name\n";
  $this->assert_str_equals($props->{"cmis:name"}->getValue, $name);
}

sub test_Object_getPropertiesFiltered {
  my $this = shift;

  require WebService::Cmis::Object;
  my $repo = $this->getRepository;

  # SMELL: the root folder doesn't have a creator for some repos

  my $obj = $repo->getRootFolder;
  $this->assert_not_null($obj, "ERROR: no root folder found\n\n");

  ##### 1rst call
  my $props1 = $obj->getProperties("lastModifiedBy");
  #print STDERR "found ".scalar(keys %$props1)." property\n";

  $this->assert_num_equals(1, scalar(keys %$props1));

  my $prop1 = $props1->{"cmis:lastModifiedBy"}->getValue;
  $this->assert_not_null($prop1);

  ##### 2nd call
  my $props2 = $obj->getProperties("cmis:objectTypeId");
  #print STDERR "found ".scalar(keys %$props2)." property\n";

  $this->assert_num_equals(1, scalar(keys %$props2));

  my $prop2 = $props2->{"cmis:objectTypeId"}->getValue;
  $this->assert_not_null($prop2);

  ##### 3nd call
  my $props3 = $obj->getProperties("cmis:createdBy, cmis:creationDate");
  #print STDERR "found ".scalar(keys %$props3)." property\n";
  #print STDERR "props3=".join(', ', keys %$props3)."\n";

  $this->assert_num_equals(2, scalar(keys %$props3));

  # SMELL: fails on nuxeo
  my $prop3 = $props3->{"cmis:createdBy"}->getValue;
  #print STDERR "prop3=$prop3\n";
  $this->assert_not_null($prop3);

  # SMELL: fails on nuxeo
  my $prop4 = $props3->{"cmis:creationDate"}->getValue;
  $this->assert_not_null($prop4);

}

sub test_Object_getParents_root {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;
  $this->assert_not_null($root, "ERROR: no root folder found\n\n");

  my $parents;
  try {
    $parents = $root->getObjectParents;
  } catch WebService::Cmis::NotSupportedException with {
    my $error = shift;
    $this->assert(ref($error), "WebService::Cmis::NotSupportedException");
    $this->assert_matches('^object does not support getObjectParents', $error);
  };

  $this->assert_null($parents, "ERROR: root doesn't have a parent\n\n");
}

sub test_Object_getParents_children {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;
  $this->assert_not_null($root, "ERROR: no root folder found\n\n");
  #print STDERR "root=".$root->getId."\n";

  my $children = $root->getChildren;
  #print STDERR "found ".$children->getSize." children in root folder\n";

  while (my $obj = $children->getNext) {
    my $parents = $obj->getObjectParents;
    $this->assert_not_null($parents);

    my $parent;
    if ($parents->isa("WebService::Cmis::AtomFeed")) {
      $this->assert_num_equals(1, $parents->getSize);
      $parent = $parents->getNext;
    } else {
      $parent = $parents;
    }

    #print STDERR "object=".$obj->getName."\n";
    #print STDERR "parent=".$parent->getId."\n";

    $this->assert_str_equals($root->getId, $parent->getId, "ERROR: child doesn't point back to its parent\n\n");
  }
}

sub test_Object_getParents_subchildren {
  my $this = shift;
  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;
  $this->assert_not_null($root, "ERROR: no root folder found\n\n");

  my $children = $root->getChildren;
  #print STDERR "found ".$children->getSize." children in root folder\n";

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
  #print STDERR "found ".$children->getSize." children in sub folder ".$folder->getId.", url=".$folder->getSelfLink."\n";

  while(my $obj = $children->getNext) {
    my $parents = $obj->getObjectParents;
    #print STDERR "obj=$obj, name=".$obj->getName."\n";
    #print STDERR "parents=$parents, ref=".ref($parents)."\n";
    my $parent;
    if ($parents->isa("WebService::Cmis::AtomFeed")) {
      $this->assert_num_equals(1, $parents->getSize);
      $parent = $parents->getNext;
    } else {
      $parent = $parents;
    }
    $this->assert($parent->isa("WebService::Cmis::Object"));
  }
}

sub test_Object_getAppliedPolicies {
  my $this = shift;

  my $repo = $this->getRepository;
  my $rootCollection = $repo->getCollection(ROOT_COLL);
  $this->assert_not_null($rootCollection, "ERROR: can't fetch root collection\n\n");

  while(my $child = $rootCollection->getNext) {
    my $policies;
    my $exceptionOkay = 0;
    
    try {
      $policies = $child->getAppliedPolicies;
    } catch WebService::Cmis::NotSupportedException with {
      my $error = shift;
      $this->assert_str_equals('This object has canGetAppliedPolicies set to false', $error, "ERROR: unexpected error: ".$error."\n\n");
      $exceptionOkay = 1;
    };
    next if $exceptionOkay;

    $this->assert_not_null($policies);
    #print STDERR "found ".$policies->getSize." policies for".$child->getName."\n";
    while(my $obj = $policies->getNext) {
      $this->assert_str_equals('WebServices::Cmis::Policy', ref($obj));
      #print STDERR "obj=".$obj->getName."\n";
    }
  }
}

# SMELL: fails on nuxeo
sub test_Object_getRelations {
  my $this = shift;

  my $repo = $this->getRepository;
  my $rootCollection = $repo->getCollection(ROOT_COLL);
  $this->assert_not_null($rootCollection, "ERROR: can't fetch root collection\n\n");

  while(my $child = $rootCollection->getNext) {
    my $rels = $child->getRelationships;
    $this->assert_not_null($rels);
    #print STDERR "found ".$rels->getSize." relations for".$child->getName."\n";
    while(my $obj = $rels->getNext) {
      $this->assert_str_equals('WebServices::Cmis::Policy', ref($obj));
      #print STDERR "obj=".$obj->getName."\n";
    }
  }
}

sub test_Repository_getRootFolder {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  $this->assert_not_null($obj, "ERROR: can't fetch root folder\n\n");
  #print STDERR "obj=".$obj->toString." ($obj)\n";

  my $props = $obj->getProperties;
  #print STDERR $props->{"cmis:path"}{displayName}."=".$props->{"cmis:path"}->getValue."\n";
  $this->assert_str_equals("/", $props->{"cmis:path"}->getValue);
  $this->assert_str_equals("", $props->{"cmis:parentId"}->getValue||"");
}

sub test_Repository_getObjectByPath {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;
  my $obj = $repo->getObjectByPath;

  $this->assert_not_null($root, "ERROR: no root folder found\n\n");
  #print STDERR "obj=".$obj->getId.", name=".$obj->getName.", path=".$obj->getPath."\n";

  $this->assert_str_equals($root->getId, $obj->getId);
}

sub test_Repository_getObjectByPath_Sites {
  my $this = shift;
  my $repo = $this->getRepository;

  # TODO: /Sites only available in default alfresco; use another example path
  my $examplePath = '/Sites';
  my $obj = $repo->getObjectByPath($examplePath);

  #print STDERR "obj=".$obj->getId.", name=".$obj->getName.", path=".$obj->getPath."\n";
  $this->assert_not_null($obj, "ERROR: $examplePath not found\n\n");
  $this->assert_str_equals($examplePath, $obj->getPath);
}

sub test_Repository_getObjectByPath_Unknown {
  my $this = shift;
  my $repo = $this->getRepository;

  my $obj;

  try {
    $obj = $repo->getObjectByPath('/This/Folder/Does/Not/Exist');
  } catch WebService::Cmis::ClientException with {
    my $error = shift;
    $this->assert_not_null($error);
    $this->assert_matches('^404 Not Found', $error);
    $this->assert_null($obj);
  };

}

sub test_Object_getAllowableActions {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $this->getTestDocument;

  my $allowableActions = $obj->getAllowableActions;
  $this->assert_not_null($allowableActions, "ERROR: can't get allowable actions\n\n");
  foreach my $action (keys %$allowableActions) {
    #print STDERR "$action=$allowableActions->{$action}\n";
    $this->assert_matches('^can', $action);
    $this->assert_matches('^(0|1)$', $allowableActions->{$action});
  }
}

sub test_Repository_getObject {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;

  my $obj = $repo->getObject($root->getId);
  $this->assert_str_equals($root->getId, $obj->getId);
}

sub test_Object_getObject {
  my $this = shift;

  require WebService::Cmis::Object;

  my $repo = $this->getRepository;

  my $rootFolderId = $repo->getRepositoryInfo->{'rootFolderId'};
  my $obj = new WebService::Cmis::Object(repository=>$repo, id => $rootFolderId);

  $this->assert_not_null($obj, "ERROR: can't create an Object\n\n");
  #print STDERR "obj=$obj\n";
}


sub test_Object_getName {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  my $props = $obj->getProperties;
  my $name = $props->{"cmis:name"}->getValue;
  $this->assert_not_null($name);
  #print STDERR "cmis:name=$title\n";
  $this->assert_str_equals($name, $obj->getProperty("cmis:name"));
}


sub test_Object_getSummary {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;

  my $summary = $root->getSummary;
  $this->assert_not_null($summary);
  #print STDERR "summary=$summary\n";
}

sub test_Object_getPublished {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;

  my $published = $root->getPublished;
  $this->assert_not_null($published);
  $this->assert_matches('^\d+', $published);

  
  #require WebService::Cmis::Property;
  #print STDERR "published=".WebService::Cmis::Property::formatDateTime($published)." ($published)\n";
}


sub test_Object_getTitle {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;

  my $title = $root->getTitle;
  $this->assert_not_null($title);
  #print STDERR "title=$title\n";
}


sub test_Object_getLinkFirst {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  my $href = $obj->getLink('*');
  $this->assert_not_null($href);
  #print STDERR "href=$href\n";

  $href =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port
  $this->assert_matches('^'.$this->{connection}{url}, $href);
}

sub test_Object_getLink {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  my $href = $obj->getLink(ACL_REL);
  #print STDERR "href=$href\n";
  $this->assert_not_null($href);

  $href =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port
  $this->assert_matches('^'.$this->{connection}{url}.'.*acl', $href);
}

sub test_Object_getLinkFiltered {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  my $href = $obj->getLink(DOWN_REL, ATOM_XML_FEED_TYPE_P);
  $this->assert_not_null($href);

  $href =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port
  $this->assert_matches('^'.$this->{connection}{url}.'.*children', $href);

}

sub test_Object_getSelfLink {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  my $href = $obj->getSelfLink;
  $this->assert_not_null($href);
  $this->assert_not_null($href);

  $href =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port
  $this->assert_matches('^'.$this->{connection}{url}, $href);
}

sub test_Object_getACL {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $repo->getRootFolder;

  my $acl;
  my $exceptionOk = 0;
  try {
    $acl = $obj->getACL;
  } catch WebService::Cmis::NotSupportedException with {
    my $error = shift;
    $this->assert_str_equals("This repository does not support ACLs", $error);
    $exceptionOk = 1;
  };
  return if $exceptionOk;

  $this->assert_not_null($acl);

  #print STDERR $acl->{xmlDoc}->toString."\n";

  foreach my $ace ($acl->getEntries) {
    $this->assert_str_equals("WebService::Cmis::ACE", ref($ace));
    #print STDERR $ace->toString."\n";
  }

  # SMELL: add some asserts that make sense
}

sub test_ACL_getXmlDoc {
  my $this = shift;

  my $origString = <<'HERE';
<?xml version="1.0" encoding="UTF-8"?>
<cmis:acl xmlns:cmis="http://docs.oasis-open.org/ns/cmis/core/200908/">
  <cmis:permission>
    <cmis:principal>
      <cmis:principalId>GROUP_EVERYONE</cmis:principalId>
    </cmis:principal>
    <cmis:direct>false</cmis:direct>
    <cmis:permission>cmis:read</cmis:permission>
  </cmis:permission>
  <cmis:permission>
    <cmis:principal>
      <cmis:principalId>GROUP_EVERYONE</cmis:principalId>
    </cmis:principal>
    <cmis:direct>false</cmis:direct>
    <cmis:permission>{http://www.alfresco.org/model/content/1.0}cmobject.Consumer</cmis:permission>
  </cmis:permission>
</cmis:acl>
HERE

  require WebService::Cmis::ACL;
  my $xmlDoc = XML::LibXML->load_xml(string => $origString);

  my $acl = new WebService::Cmis::ACL(xmlDoc=>$xmlDoc);
  my $newString = $acl->getXmlDoc->toString(1);

  #print STDERR "orig:\n$origString\n";
  #print STDERR "new:\n$newString\n";

  $this->assert_str_equals($origString, $newString);
}

sub test_Repository_getLink {
  my $this = shift;

  my $repo = $this->getRepository;
#  $repo->reload unless defined $repo->{xmlDoc};
#  my $linkNodes = $repo->{xmlDoc}->findnodes('//atom:link');
#  print STDERR "found ".$linkNodes->size." links\n";
#  print STDERR $_->toString."\n", foreach $linkNodes->get_nodelist;
#  print STDERR "\n";

  my $repoUrl = $this->{connection}{url};
  $repoUrl =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port

  # SMELL: check capabilities
  foreach my $rel (FOLDER_TREE_REL, ROOT_DESCENDANTS_REL, TYPE_DESCENDANTS_REL, CHANGE_LOG_REL) {
    my $href = $repo->getLink($rel);
    $href =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port
    $this->assert_not_null($href, "ERROR: link for $rel not found\n\n");
    $this->assert_matches("^$repoUrl", $href);
    #print STDERR "found rel=$rel, href=$href\n";
  }
}

sub test_Repository_getLink_unknown {
  my $this = shift;

  my $repo = $this->getRepository;
  my $href = $repo->getLink("foobar");
  $this->assert_null($href);
}

sub test_AtomFeed {
  my $this = shift;

  my $repo = $this->getRepository;

  my $resultSet = $repo->getCollection(ROOT_COLL);
  my $nrResults = $resultSet->getSize;
  $this->assert($nrResults > 0, "ERROR: no objects in root collection\n\n");
  #print STDERR "found $nrResults results\n";

  while(my $obj = $resultSet->getNext) {
    $this->assert($obj->isa("WebService::Cmis::Object"), "ERROR: not a cmis object\n\n");
    #print STDERR "name=".$obj->getName." type=".$obj->getTypeId." path=".($obj->getPath||'')."\n";
    #print STDERR "toString=".$obj->toString."\n";
    $this->assert_not_null($obj->getName);
    $this->assert_not_null($obj->getTypeId);
    $this->assert_not_null($obj->toString);
    if ($obj->isa("WebService::Cmis::Folder")) {
      $this->assert_not_null($obj->getPath);
      $this->assert_matches("^/", $obj->getPath);
      $this->assert_matches($obj->getName.'$', $obj->getPath);
    }
    $this->assert(!ref($obj->toString), "ERROR: illegal objectId\n\n");
  }
}

# self link on xCmis broken
sub test_AtomFeed_rewind {
  my $this = shift;

  my $repo = $this->getRepository;

  my $resultSet = $repo->getCollection(ROOT_COLL);
  my $size1 = $resultSet->getSize;
  #print STDERR "resultSet1=".$resultSet->{xmlDoc}->toString(1)."\n";

  $resultSet->rewind;
  #print STDERR "resultSet2=".$resultSet->{xmlDoc}->toString(1)."\n";

  my $size2 = $resultSet->getSize;

  #print STDERR "size1=$size1, size2=$size2\n";

  $this->assert_num_equals($size1, $size2);
}

sub test_AtomFeed_getSelfLinks_RootCollection {
  my $this = shift;
  my $repo = $this->getRepository;
  my $collection = $repo->getCollection(ROOT_COLL);
  my $nrEntries = $collection->getSize;
  #print STDERR "found $nrEntries objects in root collection\n";
  #print STDERR "self url of collection=".$collection->getLink(SELF_REL)."\n";

  my $index = 0;
  if ($collection->getSize > 0) {
    my $obj = $collection->getNext;
    $this->assert_not_null($obj, "ERROR: no object found in non-zero feed\n");
    do {
      $this->assert($obj->isa("WebService::Cmis::Object"), "ERROR: not a cmis object\n\n");
      my $id = $obj->getId;
      my $url = $obj->getSelfLink;
      my $name = $obj->getName;
      my $summary = $obj->getSummary;
      $this->assert_not_null($id);
      $this->assert_not_null($url);
      $this->assert_not_null($name);
      $this->assert_not_null($summary);
      #print STDERR "name=$name, summary=$summary, url=$url\n";
      $id =~ s/^.*\///;
      $url =~ s/^.*\///;
      $this->assert_str_equals($id, $url, "ERROR: url suffix '$url' doesn't match id suffix '$id'\n\n");
      $index++;
    } while ($obj = $collection->getNext);
  }

  $this->assert_num_equals($nrEntries, $index);
}

sub test_AtomFeed_getSelfLinks_getDescendants {
  my $this = shift;
  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;
  my $resultSet = $root->getDescendants(depth=>2);
  #print STDERR "found ".$resultSet->getSize." objects in result set\n";
  #print STDERR "self url of result set=".$resultSet->getLink(SELF_REL)."\n";

  while(my $obj = $resultSet->getNext) {
    $this->assert($obj->isa("WebService::Cmis::Object"), "ERROR: not a cmis object\n\n");
    my $id = $obj->getId;
    my $url = $obj->getSelfLink;
    #print STDERR "name=$name, id=$id, url=$url\n";
    $id =~ s/^.*\///;
    $url =~ s/^.*\///;
    $this->assert_str_equals($id, $url, "ERROR: url suffix '$url' doesn't match id suffix '$id'\n\n");
  }
}

sub test_AtomFeed_reverse {
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
    $this->assert_not_null($obj, "ERROR: no object found in non-zero feed\n");

    do {
      $this->assert($obj->isa("WebService::Cmis::Object"), "ERROR: not a cmis object\n\n");
      $index++;

      $this->assert($collection->{index} >= 0, "ERROR: illegal index in AtomFeed\n\n");

      $obj = $collection->getPrev;
      #print STDERR  "3 - index=$collection->{index}\n";

      #print STDERR "obj=".$obj->toString."\n";
      $this->assert($obj->toString ne $lastObj->toString, "ERROR: can't travel backwards in atom feed\n\n") if $obj;

    } while ($obj);
  }

  $this->assert_num_equals($nrEntries, $index);
}

sub FAILS_test_AtomFeed_paging {
  my $this = shift;
  my $repo = $this->getRepository;

  my $changes1 = $repo->getContentChanges;
  my $size = $changes1->getSize;

  print STDERR "size1=$size\n";
  #print STDERR "### changes:\n".$changes1->{xmlDoc}->toString(1)."\n###\n";

  my %entries1 = ();
  my @keys = ();
  while (my $entry = $changes1->getNext) {
    my $id = $entry->getId;
    my $changeTime = $entry->getChangeTime;
    my $key = "$id-$changeTime";
    print STDERR "key1=$key\n";
    push @keys, $key;

    $this->assert_null($entries1{$key});
    $entries1{$key} = $entry;
  }

  print STDERR "index1=".scalar(keys %entries1)."\n";

  my $changes2 = $repo->getContentChanges(maxItems=>10);
  my $size2 = $changes2->getSize;
  print STDERR "size2=$size2\n";

  my %entries2 = ();
  while (my $entry = $changes2->getNext) {
    my $id = $entry->getId;
    my $changeTime = $entry->getChangeTime;
    my $key = "$id-$changeTime";
    print STDERR "key2=$key\n";

    $this->assert_null($entries2{$key});
    $entries2{$key} = $entry;
  }

  print STDERR "index2=".scalar(keys %entries2)."\n";

  foreach my $key (@keys) {
    #print STDERR "key=$key\n";
    $this->assert_not_null($entries2{$key}, "ERROR: entry $key in first set not found in second\n\n");
  }
}

sub test_Folder_getChildrenLink {
  my $this = shift;
  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder();
  my $childrenLink = $root->getChildrenLink();
  #print STDERR "childrenLink=$childrenLink\n";

  my $href = $this->{connection}{url};
  $href =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port
  $childrenLink =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port

  $this->assert_matches("^$href", $childrenLink);
}

sub test_Folder_getChildren {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder();
  my $children = $root->getChildren();
  #print STDERR "children=$children\n";
  while(my $obj = $children->getNext) {
    #print STDERR $obj->getPath ."(".$obj->getTypeId.")\n";
    $this->assert($obj->isa('WebService::Cmis::Object'));
  }
}

sub test_Folder_getDescendantsLink {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder();
  my $descendantsLink = $root->getDescendantsLink();
  #print STDERR "descendantsLink=$descendantsLink\n";

  my $href = $this->{connection}{url};
  $href =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port
  $descendantsLink =~ s/^(http:\/\/[^\/]+?):80\//$1\//g; # remove bogus :80 port

  $this->assert_matches("^$href", $descendantsLink);
}

sub test_Folder_getDescendants {
  my $this = shift;

  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder();
  my $descendants;
  my $exceptionOk = 0;

  try {
    $descendants = $root->getDescendants(depth=>2); 
  } catch WebService::Cmis::NotSupportedException with {
    my $error = shift;
    $this->assert_str_equals("This repository does not support getDescendants", $error);
    $exceptionOk = 1;
  };
  return if $exceptionOk;

  #print STDERR "found ".$descendants->getSize." descdendants at ".$root->getName."\n";
  while(my $obj = $descendants->getNext) {
    #print "path=".($obj->getPath||'').", title=".$obj->getTitle.", summary=".$obj->getSummary.", url=".$obj->getSelfLink."\n";
    $this->assert_not_null($obj);
    $this->assert($obj->isa("WebService::Cmis::Object"));
  }
}

# xCmis doesn't support filtering by type
sub test_Object_getFolderParent {
  my $this = shift;
  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;

  my $rootParent = $root->getFolderParent;
  $this->assert_null($rootParent);

  my $subfolder = $root->getChildren(types=>"folders")->getNext;
  $this->assert_not_null($subfolder);
  $this->assert_str_equals("WebService::Cmis::Folder", ref($subfolder));
  
  my $parent = $subfolder->getFolderParent;
  $this->assert_str_equals($root->getId, $parent->getId);
  #print STDERR "parent=".$parent->getId."\n";
}

sub test_Folder_getFolderTree {
  my $this = shift;
  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;

  my $tree = $root->getFolderTree(depth=>2);
  #print STDERR "found ".$tree->getSize." objects\n";
  while(my $obj = $tree->getNext) {
    #print STDERR "obj=$obj, name=".$obj->getName.", id=".$obj->getId.", url=".$obj->getSelfLink."\n";
    $this->assert($obj->isa('WebService::Cmis::Folder'));
  }
}

sub test_Repository_getCheckedOutDocs {
  my $this = shift;

  my $repo = $this->getRepository;

  my $obj = $this->getTestDocument;
  $obj->checkOut;

  my $checkedOutDocs = $repo->getCheckedOutDocs;
  $this->assert_not_null($checkedOutDocs, "ERROR: can't get checked out docs\n\n");

  #print STDERR "found ".$checkedOutDocs->getSize." checked out document(s)\n";
  $this->assert_not_null($checkedOutDocs->getSize, "ERROR: should have at least one document checked out\n\n");

  while(my $obj = $checkedOutDocs->getNext) {
    #print STDERR "name=".$obj->getName.", id=".$obj->getId.", url=".$obj->getSelfLink."\n";
    $this->assert($obj->isa('WebService::Cmis::Document'));
  }

  $obj->cancelCheckOut;
}

sub test_Repository_getUnfiledDocs {
  my $this = shift;

  my $repo = $this->getRepository;

  my $unfiledDocs = $repo->getUnfiledDocs;
  $this->assert_not_null($unfiledDocs, "ERROR: can't get unfiled docs\n\n");

  #print STDERR "found ".$unfiledDocs->getSize." unfiled document(s)\n";

  while(my $obj = $unfiledDocs->getNext) {
    print STDERR "name=".$obj->getName.", id=".$obj->getId.", url=".$obj->getSelfLink."\n";
    $this->assert($obj->isa('WebService::Cmis::Document'));
  }

  # TODO create an unfiled document and test it
  #$this->assert(0, "WARNING: create an unfiled document and verify it is in the unfiled collection\n\n");
}

sub test_Repository_getTypeDefinitions {
  my $this = shift;

  my $repo = $this->getRepository;

  my $typeDefs = $repo->getTypeDefinitions;
  $this->assert_not_null($typeDefs, "ERROR: can't get type definitions\n\n");

  #print STDERR "found ".$typeDefs->getSize." type definition(s)\n";

  while(my $objectType = $typeDefs->getNext) {
    $this->assert_str_equals('WebService::Cmis::ObjectType', ref($objectType));
    $this->assert_not_null($objectType->getId);
    $this->assert_not_null($objectType->getDisplayName);
    $this->assert_not_null($objectType->getQueryName);
    #print "id=".$objectType->getId.", displayName=".$objectType->getDisplayName.", description=".$objectType->getDescription.", link=".$objectType->getLink."\n";
    $objectType->reload;
    $this->assert_not_null($objectType->getId);
    $this->assert_not_null($objectType->getDisplayName);
    $this->assert_not_null($objectType->getQueryName);
  }
}

sub test_Repository_getTypeChildren {
  my $this = shift;
  my $repo = $this->getRepository;

  # get type defs
  foreach my $typeId (undef, 'cmis:document', 'cmis:policy', 'cmis:folder', 'cmis:relationship') {
    my $set = $repo->getTypeChildren($typeId);
    $this->assert_not_null($set);
    $this->assert($set->getSize > 0);

    #print STDERR "found ".$set->getSize." objects(s)\n";
    while(my $objectType = $set->getNext) {
      $this->assert_str_equals('WebService::Cmis::ObjectType', ref($objectType));
      #print "id=".$objectType->getId.", displayName=".$objectType->getDisplayName.", description=".$objectType->getDescription.", link=".$objectType->getLink."\n";
    }
  }
}

sub test_Repository_getTypeDescendants {
  my $this = shift;
  my $repo = $this->getRepository;

  # get type defs
  foreach my $typeId (undef, 'cmis:document', 'cmis:policy', 'cmis:folder', 'cmis:relationship') {
    my $set = $repo->getTypeDescendants($typeId, depth=>1);
    $this->assert_not_null($set);
    #print STDERR "found ".$set->getSize." objects(s) of type ".($typeId||'undef')."\n";
    $this->assert($set->getSize > 0);

    while(my $objectType = $set->getNext) {
      $this->assert_str_equals('WebService::Cmis::ObjectType', ref($objectType));
      #print "id=".$objectType->getId.", displayName=".$objectType->getDisplayName.", description=".$objectType->getDescription.", link=".$objectType->getLink."\n";
    }
  }
}

sub test_Document_getAllVersions {
  my $this = shift;
  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;
  my $resultSet = $root->getDescendants(depth=>2);
  $this->assert_not_null($resultSet, "ERROR: can't fetch results\n\n");

  #print STDERR "found ".$resultSet->getSize." documents in root collection\n";

  while(my $obj = $resultSet->getNext) {
    next unless $obj->isa("WebService::Cmis::Document");

    #print STDERR "### versions in ".$obj->getId.", url=".$obj->getSelfLink."\n";
    my $allVersions = $obj->getAllVersions;
    $this->assert_not_null($allVersions);
    $this->assert($allVersions->getSize > 0, "ERROR: no versions for ".$obj->toString."\n\n");

    while(my $version = $allVersions->getNext) {
      #print STDERR "version=".$version->toString."\n";
      my $props = $version->getProperties;

      # SMELL: which of these are standard, which are nice-to-haves by alfresco?
      foreach my $propId qw(cmis:contentStreamFileName cmis:name
        cmis:baseTypeId cmis:isImmutable cmis:isLatestMajorVersion cmis:changeToken
        cmis:isVersionSeriesCheckedOut cmis:objectTypeId cmis:createdBy
        cmis:versionSeriesId cmis:versionSeriesCheckedOutBy cmis:lastModificationDate
        cmis:versionSeriesCheckedOutId cmis:isLatestVersion cmis:objectId
        cmis:checkinComment cmis:versionLabel cmis:creationDate cmis:contentStreamId
        cmis:contentStreamLength cmis:contentStreamMimeType cmis:lastModifiedBy
        cmis:isMajorVersion) {
        #print STDERR "   $propId=".($props->{$propId}->getValue||'')."\n";
        $this->assert_not_null($props->{$propId}, "ERROR: property $propId not defined\n\n");
      }
    }
  }
}

sub test_Repository_getQueryXmlDoc {
  my $this = shift;
  my $repo = $this->getRepository;

  my $xmlDoc = $repo->_getQueryXmlDoc("select * from cmis:document", foo=>"bar");

  #print STDERR "xmlDoc=$xmlDoc\n";
  my $testString = <<'HERE';
<?xml version="1.0" encoding="UTF-8"?>
<query xmlns="http://docs.oasis-open.org/ns/cmis/core/200908/">
  <statement><![CDATA[select * from cmis:document]]></statement>
  <foo>bar</foo>
</query>
HERE

  $this->assert_str_equals($testString, $xmlDoc->toString(1));
}

sub test_Repository_query {
  my $this = shift;
  my $repo = $this->getRepository;

  foreach my $typeId ('cmis:folder', 'cmis:document', 'cmis:policy') {
    my $feed = $repo->query("select * from $typeId", maxItems=>1);
    $this->assert_not_null($feed);
    $this->assert_not_null($feed->getTitle);
    $this->assert_not_null($feed->getGenerator);
    $this->assert_not_null($feed->getUpdated);
    $this->assert_matches('^\d+$', $feed->getUpdated);
    $this->assert_matches('^\d+$', $feed->getSize);

    require WebService::Cmis::Property;
    my $updated = WebService::Cmis::Property::formatDateTime($feed->getUpdated);

    #print STDERR "title=".$feed->getTitle."\n";
    #print STDERR "generator=".$feed->getGenerator."\n";
    #print STDERR "updated=$updated\n";
    #print STDERR "numItems=".$feed->getSize."\n";

    # TODO: check paging
  }
}

sub test_Repository_getContentChanges {
  my $this = shift;
  my $repo = $this->getRepository;

  my $changeLogToken = $repo->getRepositoryInfo->{'latestChangeLogToken'};
  $this->assert_not_null($changeLogToken, "ERROR: change log not configured\n\n");
  #print STDERR "changeLogToken=$changeLogToken\n";

  my $changes = $repo->getContentChanges(maxItems=>10);

  #print STDERR $changes->{xmlDoc}->toString(1)."\n";

  my $nrChanges = $changes->getSize;
  $this->assert($nrChanges > 0, "ERROR: no changes found\n\n");
  #print STDERR "found ".$changes->getSize." changes\n";

  require WebService::Cmis::Property;
  my $index = 0;
  while(my $changeEntry = $changes->getNext) {
    last if $index++ > 10;

    $this->assert_str_equals("WebService::Cmis::ChangeEntry", ref($changeEntry));

    my $id = $changeEntry->getId;
    $this->assert_not_null($id);

    my $changeType = $changeEntry->getChangeType;
    $this->assert_not_null($id);
    $this->assert_matches('^(created|updated|deleted|security)$',$changeType);

    my $changeTime = $changeEntry->getChangeTime;
    $this->assert_matches('^\d+$', $changeTime);
    $this->assert_not_null($id);

    $changeTime = WebService::Cmis::Property::formatDateTime($changeTime);
    $this->assert_not_null($id);

    my $objectId = $changeEntry->getObjectId;
    $this->assert_not_null($objectId);

    #print STDERR "changeEntry id=$id, type=$changeType, time=$changeTime, objectId=$objectId\n";

    if ($changeType eq 'deleted') {
      #print STDERR "- deleted $objectId\n";
    } elsif ($changeType =~ /created|updated/) {
      my $obj = $repo->getObject($objectId);
      if ($obj) {
        #print STDERR "+ changed title=".$obj->getTitle.", type=".$obj->getTypeId."\n";
      }
    }

    my $acl = $changeEntry->getACL;
    next unless $acl;
    foreach my $ace ($acl->getEntries) {
      $this->assert_str_equals("WebService::Cmis::ACE", ref($ace));
      #print STDERR $ace->toString."\n";
    }
  }
  #print STDERR "index=$index\n";
}

sub test_Repository_createEntryXmlDoc_1 {
  my $this = shift;
  my $repo = $this->getRepository;

  my $xmlDoc = $repo->createEntryXmlDoc();
  #print STDERR $xmlDoc->toString(1)."\n";

  my $xmlSource = <<'HERE';
<?xml version="1.0" encoding="UTF-8"?>
<entry xmlns="http://www.w3.org/2005/Atom" xmlns:app="http://www.w3.org/2007/app" xmlns:cmisra="http://docs.oasis-open.org/ns/cmis/restatom/200908/">
  <cmisra:object xmlns:cmisra="http://docs.oasis-open.org/ns/cmis/restatom/200908/" xmlns:cmis="http://docs.oasis-open.org/ns/cmis/core/200908/">
    <cmis:repositoryId xmlns:cmis="http://docs.oasis-open.org/ns/cmis/core/200908/">7baeb5c7-d5ac-4f09-8d1d-6bca90673a29</cmis:repositoryId>
  </cmisra:object>
</entry>
HERE

  $this->assert_str_equals($xmlSource, $xmlDoc->toString(1));
}

sub test_Repository_createEntryXmlDoc_2 {
  my $this = shift;
  my $repo = $this->getRepository;

  require WebService::Cmis::Property;

  #print "nameProperty=".$nameProperty->toString."\n";

  my $xmlDoc = $repo->createEntryXmlDoc(
    properties => [
      WebService::Cmis::Property::newString(
        id => 'cmis:name',
        value => "hello world",
      ),
      WebService::Cmis::Property::newBoolean(
        id=>"cmis:isLatestMajorVersion",
        displayName=>"Is Latest Major Version",
        queryName=>"cmis:isLatestMajorVersion",
        value=>0,
      ),
      WebService::Cmis::Property::newDateTime(
        id=>"cmis:creationDate",
        displayName=>"Creation Date",
        queryName=>"cmis:creationDate",
        value=>WebService::Cmis::Property::parseDateTime("2011-01-25T13:22:28+01:00"),
      ),
      WebService::Cmis::Property::newString(
        id => 'cm:taggable',
        queryName => 'cm:taggable',
        displayName => 'Tags',
        value => ["foo", "bar", "baz"],
      ),
    ]
  );

  my $testString = <<'HERE';
<?xml version="1.0" encoding="UTF-8"?>
<entry xmlns="http://www.w3.org/2005/Atom" xmlns:app="http://www.w3.org/2007/app" xmlns:cmisra="http://docs.oasis-open.org/ns/cmis/restatom/200908/">
  <cmisra:object xmlns:cmisra="http://docs.oasis-open.org/ns/cmis/restatom/200908/" xmlns:cmis="http://docs.oasis-open.org/ns/cmis/core/200908/">
    <cmis:properties xmlns:cmis="http://docs.oasis-open.org/ns/cmis/core/200908/">
      <cmis:propertyString propertyDefinitionId="cmis:name">
        <cmis:value>hello world</cmis:value>
      </cmis:propertyString>
      <cmis:propertyBoolean displayName="Is Latest Major Version" propertyDefinitionId="cmis:isLatestMajorVersion" queryName="cmis:isLatestMajorVersion">
        <cmis:value>false</cmis:value>
      </cmis:propertyBoolean>
      <cmis:propertyDateTime displayName="Creation Date" propertyDefinitionId="cmis:creationDate" queryName="cmis:creationDate">
        <cmis:value>2011-01-25T13:22:28+01:00</cmis:value>
      </cmis:propertyDateTime>
      <cmis:propertyString displayName="Tags" propertyDefinitionId="cm:taggable" queryName="cm:taggable">
        <cmis:value>foo</cmis:value>
        <cmis:value>bar</cmis:value>
        <cmis:value>baz</cmis:value>
      </cmis:propertyString>
    </cmis:properties>
    <cmis:repositoryId xmlns:cmis="http://docs.oasis-open.org/ns/cmis/core/200908/">7baeb5c7-d5ac-4f09-8d1d-6bca90673a29</cmis:repositoryId>
  </cmisra:object>
  <title>hello world</title>
</entry>
HERE

  #print STDERR $xmlDoc->toString(1)."\n";
  $this->assert_str_equals($testString, $xmlDoc->toString(1));
}

sub test_Repository_createEmptyXmlDoc {
  my $this = shift;
  my $repo = $this->getRepository;
  my $xmlDoc = $repo->createEmptyXmlDoc;

  my $testString = <<'HERE';
<?xml version="1.0" encoding="UTF-8"?>
<entry xmlns="http://www.w3.org/2005/Atom"/>
HERE

  #print STDERR $xmlDoc->toString(1)."\n";
  $this->assert_str_equals($testString, $xmlDoc->toString(1));
}

sub test_Repository_createEntryXmlDoc_contentFile {
  my $this = shift;
  my $repo = $this->getRepository;

  my $testFile = "./CmisPlugin/data/free.jpg";
  $this->assert(-e $testFile, "ERROR: testFile=$testFile not found\n\n");

  my $xmlDoc = $repo->createEntryXmlDoc(
    contentFile=>$testFile
  );

  #print STDERR $xmlDoc->toString(1)."\n";
  #$this->assert_str_equals($testString, $xmlDoc->toString(1));
}

sub test_Repository_createDocument_filed {
  my $this = shift;
  my $repo = $this->getRepository;

  # set up test folder
  my $document = $this->getTestDocument;
 
  $document = $repo->getObjectByPath("/".$this->getTestFolderName."/free.jpg");
  $this->assert_not_null($document, "ERROR: can't find uploaded object ... should be available now");
}

sub test_Repository_createDocument_unfiled {
  my $this = shift;
  my $repo = $this->getRepository;

  my $testFile = "./CmisPlugin/data/free.jpg";
  $this->assert(-e $testFile, "ERROR: testFile=$testFile not found\n\n");

  my $error;
  try {
    my $document = $repo->createDocument(
      "free.jpg",
      contentFile=>$testFile
    );
  } catch WebService::Cmis::NotSupportedException with {
    $error = shift;

    my $canUnfiling = $repo->getCapabilities->{'Unfiling'};
    $this->assert_num_equals(0, $canUnfiling, "ERROR: exception even though canUnfiling=$canUnfiling\n\n");
  };
}

sub test_Repository_createFolder {
  my $this = shift;
  my $repo = $this->getRepository;

  my $folder = $this->getTestFolder;

  $folder = $repo->getObjectByPath("/".$this->getTestFolderName);
  $this->assert_not_null($folder, "ERROR: folder should be available now\n\n");
}

sub test_Document_checkOut_checkIn {
  my $this = shift;

  my $repo = $this->getRepository;

  my $obj = $this->getTestDocument;
  my $isCheckedOut = $obj->isCheckedOut;
  #print STDERR "isCheckedout=$isCheckedOut\n";
  $this->assert($isCheckedOut == 0, "ERROR: test document is checked out\n\n");

  my $result = $obj->checkOut;
  $isCheckedOut = $obj->isCheckedOut;
  #print STDERR "isCheckedout=$isCheckedOut\n";
  $this->assert($isCheckedOut, "ERROR: test document is NOT checked out\n\n");

  my $checkedOutBy = $obj->getCheckedOutBy;
  #print STDERR "checkedOutBy=$checkedOutBy\n";
  $this->assert_not_null($checkedOutBy, "ERROR: no information checked out by\n\n");

  my $pwc = $obj->getPrivateWorkingCopy;
  $this->assert_not_null($pwc, "ERROR: can't get private working copy");
  #print STDERR "pwc=".$pwc->getId."\n";

  #print STDERR "obj=".$obj->getId.", pwc=".$pwc->getId."\n";
  $this->assert($obj->getId ne $pwc->getId, "ERROR: document id should be different from pwc id\n\n");

  #print STDERR "checking in\n";
  $result = $pwc->checkIn("this is a test checkin time=".time, major=>1);
  #print STDERR "result=".$result->getId."\n";

  $pwc = $obj->getPrivateWorkingCopy;
  $this->assert_null($pwc, "ERROR: there shouldn't be a private working copy anymore as the document has been checked in\n\n");
}

sub test_Document_getRenditionProperties {
  my $this = shift;

  my $repo = $this->getRepository;
  my $obj = $this->getTestDocument;

  my $renditionInfo = $obj->getRenditionInfo;
  $this->assert_not_null($renditionInfo);
  #print STDERR "renditionInfo:\n";
  foreach my $rendition (values %$renditionInfo) {
    $this->assert_not_null($rendition->{streamId});
    $this->assert_not_null($rendition->{kind});
    #print STDERR "streamId=$rendition->{streamId}\n";
    foreach my $key (keys %$rendition) {
      next if $key eq 'streamId';
      $this->assert_not_null($rendition->{$key});
      #print STDERR "   $key=$rendition->{$key}\n";
    }
  }
}

sub test_Document_getRenditionLink {
  my $this = shift;

  my $obj = $this->getTestDocument;

  my $link = $obj->getRenditionLink(kind=>"thumbnail");
  #$this->assert_not_null($link);
  #print STDERR "thumbnail=$link\n";

  $link = $obj->getRenditionLink(mimetype=>"Image");
  $this->assert_not_null($link);
  #print STDERR "image=$link\n";

  $link = $obj->getRenditionLink(mimetype=>"Image", width=>16);
  $this->assert_not_null($link);
  #print STDERR "image,16=$link\n";

  $link = $obj->getRenditionLink(mimetype=>"Image", width=>32);
  $this->assert_not_null($link);
  #print STDERR "image,32=$link\n";

  $link = $obj->getRenditionLink(kind=>"icon", height=>16);
  $this->assert_not_null($link);
  #print STDERR "icon=$link\n";

  $link = $obj->getRenditionLink(kind=>"icon", height=>11234020);
  $this->assert_null($link);
}

sub test_Document_getContentStream {
  my $this = shift;

  my $obj = $this->getTestDocument;

  my $content = $obj->getContentStream;
  my $name = $obj->getName;
  #print STDERR "name=$name\n";
  saveFile("/tmp/downloaded_$name", $content);
}

sub test_Document_getContentLink {
  my $this = shift;

  my $obj = $this->getTestDocument;
  my $contentLink = $obj->getContentLink;
  #print STDERR "content-link=$contentLink\n";
  $this->assert_not_null($contentLink, "ERROR: can't get content link for test file\n\n");
}

sub test_Document_getLatestVersion {
  my $this = shift;
  my $repo = $this->getRepository;

  $this->deleteTestDocument;
  my $doc = $this->getTestDocument;
  my $versionLabel = $doc->getProperty("cmis:versionLabel");
  #print STDERR "versionLabel=$versionLabel\n";
  $this->assert_str_equals("1.0", $versionLabel);

  my $pwc = $doc->checkOut;
  $pwc->checkIn("this is a major checkin time=".time);

  $doc = $doc->getLatestVersion;
  $versionLabel = $doc->getProperty("cmis:versionLabel");
  #print STDERR "latest versionLabel=$versionLabel\n";
  $this->assert_str_equals("2.0", $versionLabel);

  $pwc = $doc->checkOut;
  $pwc->checkIn("this is a minor test checkin time=".time, major=>0);

  $doc = $doc->getLatestVersion;
  $versionLabel = $doc->getProperty("cmis:versionLabel");
  #print STDERR "latest versionLabel=$versionLabel\n";
  $this->assert_str_equals("2.1", $versionLabel);

  $doc = $doc->getLatestVersion(major=>1);
  $versionLabel = $doc->getProperty("cmis:versionLabel");
  #print STDERR "latest major versionLabel=$versionLabel\n";
  $this->assert_str_equals("2.0", $versionLabel);

  my $checkedOutDocs = $repo->getCheckedOutDocs;
  $this->assert($checkedOutDocs->getSize == 0, "ERROR: checked out queue should be empty\n\n");
}

sub _getParents {
  my $parents = $_[0]->getObjectParents;

  my @parents = ();
  if ($parents->isa("WebService::Cmis::AtomFeed")) {
    #print STDERR "nr parents : ".$parents->getSize."\n";
    push @parents, $_ while $_ = $parents->getNext;
  } else {
    push @parents, $parents;
  }

  return @parents;
}

sub test_Document_moveTo {
  my $this = shift;
  my $repo = $this->getRepository;
  my $root = $repo->getRootFolder;


  my $obj = $this->getTestDocument;
  my ($parent1) = _getParents($obj);
  #print STDERR "parents: ".join(", ", map($_->getName, _getParents($obj)))."\n";

  $obj->moveTo($root);
  my ($parent2) = _getParents($obj);
  #print STDERR "parents: ".join(", ", map($_->getName, _getParents($obj)))."\n";

  $this->assert_num_equals(1, scalar(_getParents($obj)), "ERROR: not the same number of parents\n\n");
  $this->assert($parent1->getId ne $parent2->getId, "ERROR: should have changed folder\n\n");

  my $result = $repo->getObjectByPath("/free.jpg");
  $this->assert_not_null($result, "ERROR: document should be located in target folder\n\n");

  $result = $repo->getObjectByPath("/".$this->getTestFolderName."/free.jpg");
  $this->assert_null($result, "ERROR: document should NOT be located in source folder anymore\n\n");
}

sub test_Document_move {
  my $this = shift;
  my $repo = $this->getRepository;

  my $testFolder2 = $this->getTestFolder("2");

  my $obj = $this->getTestDocument;
  #print STDERR "parents: ".join(", ", map($_->getName, _getParents($obj)))."\n";

  $obj->move(undef, $testFolder2);
  #print STDERR "parents: ".join(", ", map($_->getName, _getParents($obj)))."\n";
  #SMELL: strange this should be multifiled now, that is have multiple parents; yet it doesn't 

  #find the document at two paths now
  my $test = $repo->getObjectByPath("/".$this->getTestFolderName("2")."/free.jpg");
  $this->assert_not_null($test, "ERROR: document not found at target location\n\n");

  $test = $repo->getObjectByPath("/".$this->getTestFolderName."/free.jpg");
  $this->assert_not_null($test, "ERROR: document not found at source location\n\n");

  # delete it once should remove it twice
  $this->deleteTestDocument;

  $test = $repo->getObjectByPath("/".$this->getTestFolderName("2")."/free.jpg");
  $this->assert_null($test, "ERROR: document should not be found at target location\n\n");

  $test = $repo->getObjectByPath("/".$this->getTestFolderName."/free.jpg");
  $this->assert_null($test, "ERROR: document should not be found at source location\n\n");
}

sub test_Document_unfile {
  my $this = shift;
  my $repo = $this->getRepository;

  my $exceptionOk = 0;
  my $obj = $this->getTestDocument;

  try {
    $obj->unfile;
  } catch WebService::Cmis::NotSupportedException with {
    my $error = shift;
    $this->assert_str_equals("This repository does not support unfiling", $error);
    $exceptionOk = 1;
  };
  return if $exceptionOk;

  my $unfiledDocs = $repo->getUnfiledDocs;
  $this->assert_not_null($unfiledDocs, "ERROR: can't get unfiled docs\n\n");

  #print STDERR "found ".$unfiledDocs->getSize." unfiled document(s)\n";

  while(my $obj = $unfiledDocs->getNext) {
    #print STDERR "name=".$obj->getName.", id=".$obj->getId.", url=".$obj->getSelfLink."\n";
    $this->assert($obj->isa('WebService::Cmis::Document'));
  }
}

sub test_Object_updateProperties {
  my $this = shift;

  my $obj = $this->getTestDocument;

  my $name1 = $obj->getName;
  my $summary1 = $obj->getSummary;
  my $title1 = $obj->getTitle;
  my $updated1 = $obj->getUpdated;

  #print STDERR "name=$name1, title=$title1, summary=$summary1, updated=$updated1, url=".$obj->getSelfLink."\n";

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

  #print STDERR "name=$name2, title=$title2, summary=$summary2 updated=$updated2\n";

  $this->assert_str_equals($newName, $name2);
  $this->assert_str_not_equals($name1, $name2);
  $this->assert_str_not_equals($updated1, $updated2);
}

sub test_Object_updateSummary {
  my $this = shift;

  my $obj = $this->getTestDocument;

  my $name1 = $obj->getName;
  my $summary1 = $obj->getSummary;
  my $title1 = $obj->getTitle;
  my $updated1 = $obj->getUpdated;

  #print STDERR "name=$name1, title=$title1, summary=$summary1, updated=$updated1, url=".$obj->getSelfLink."\n";

  sleep(1);

  my $text = 'icon showing a red button written "free" on it';
  $obj->updateSummary($text);

  my $name2 = $obj->getName;
  my $summary2 = $obj->getSummary;
  my $title2 = $obj->getTitle;
  my $updated2 = $obj->getUpdated;

  #print STDERR "name=$name2, title=$title2, summary=$summary2 updated=$updated2\n";

  $this->assert_str_equals($name1, $name2);
  $this->assert_str_equals($text, $summary2);
  $this->assert_str_not_equals($updated1, $updated2);
  $this->assert_str_not_equals($summary1, $summary2);
}

1;

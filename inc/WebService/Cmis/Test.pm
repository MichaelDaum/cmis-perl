package WebService::Cmis::Test;
use base qw(Test::Class);
use Test::More;

use strict;
use warnings;

BEGIN {
  if (!eval { require "cmis.cfg"; 1 }) {
    plan skip_all => "WARNING: You need to create a cmis.cfg. See the example file in the inc/ directory.";
  } 
}

binmode(STDERR, ":utf8");
binmode(STDOUT, ":utf8");

use WebService::Cmis qw(:collections :utils :relations :namespaces :contenttypes);
use File::Temp ();
use Error qw(:try);
use Cache::FileCache ();

require "cmis.cfg";

sub new {
  my $class = shift;
  my $connection = shift || $WebService::Cmis{DefaultConnection};

  my $config = $WebService::Cmis{Connections}{$connection};
  die "ERROR: unknown connection $connection" unless defined $config;

  $config->{testRoot} ||= $WebService::Cmis{TestRoot};
  $config->{testFile} ||= $WebService::Cmis{TestFile};

  my $this = $class->SUPER::new(@_);
  $this->{config} = $config;

  note("connection=$connection");

  return $this;
}


sub DESTROY {
  my $this = shift;

  foreach my $key (keys %{$this->{testDocuments}}) {
    $this->deleteTestDocument($key);
  }

  foreach my $key (keys %{$this->{testFolders}}) {
    $this->deleteTestFolder($key);
  }
}

sub getClient {
  my $this = shift;

  unless (defined $this->{client}) {
    my $cache;
    if ($this->{cacheEnabled}) {
      my $tempDir = File::Temp::tempdir(CLEANUP => 1);
      note("temporary cache in $tempDir");
      my $cache = Cache::FileCache->new({
        cache_root => $tempDir
        }
      );
    }

    $this->{client} = WebService::Cmis::getClient(
      %{$this->{config}},
      cache => $cache
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

sub getTestFolderPath {
  my $this = shift;
  my $key = shift;

  my $name = $this->getTestFolderName($key);
  return $this->{config}{testRoot}."/".$name;
}

sub deleteTestFolder {
  my $this = shift;
  my $key = shift;

  $key ||= 'default';
  $this->{testFolders} = {} unless defined $this->{testFolders};

  note("called deleteTestFolder");


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
    note("creating a test folder $name");
    return unless $name =~ /^WebService_Cmis_.*$/;

    my $repo = $this->getRepository;
    my $folder = $repo->getObjectByPath($this->{config}{testRoot});
    return unless defined $folder;

    my $rootFolderId = $repo->getRepositoryInfo->{'rootFolderId'};

    note("creating folder $this->{config}{testRoot}/$name");
    $this->{testFolders}{$key} = $folder->createFolder($name, summary=>"this is a test folder used by WebService::Cmis' testsuite");
    if ($this->{testFolders}{$key}->getId eq $rootFolderId) {
      print STDERR "ERROR: don't use root as test folder\n\n";
      exit; #emergency
    }

    return unless defined $this->{testFolders}{$key};
    my $allowableActions = $folder->getAllowableActions;
    return unless $allowableActions->{canCreateDocument};
    return unless $allowableActions->{canCreateFolder};
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
      note("deleting test document");
      my $pwc = $this->{testDocuments}{$key}->getPrivateWorkingCopy;
      $pwc->cancelCheckOut if $pwc;
      $this->{testDocuments}{$key}->delete;
      delete $this->{testDocuments}{$key};
    }
  } catch WebService::Cmis::ClientException with {
    my $error = shift;
    note("ERROR in deleteTestDocument: $error ... ignoring");
    # ignore
  };
}

sub getTestDocument {
  my $this = shift;
  my $key = shift;

  $key ||= 'default';

  note("called getTestDocument($key)");
  $this->{testDocuments} = {} unless defined $this->{testDocuments};

  unless (defined $this->{testDocuments}{$key}) {

    my $folder = $this->getTestFolder($key);
    my $repo = $this->getRepository;

    my $testFile = $this->{config}{testFile};
    return unless -e $testFile;

    # first delete it if it exists
    my $path = $this->getTestFolderPath($key)."/free.jpg";
    note("path=$path");

    my $document = $repo->getObjectByPath($path);
    return $document if defined $document;

    note("uploading $testFile to $path");
    $document = $folder->createDocument(
      "free.jpg",
      contentFile=>$testFile
    );
 
    return unless defined $document;

    $this->{testDocuments}{$key} = $document;
  }

  return $this->{testDocuments}{$key};
}

1;

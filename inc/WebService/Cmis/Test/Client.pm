package WebService::Cmis::Test::Client;
use base qw(WebService::Cmis::Test);
use Test::More;

use strict;
use warnings;

use Error qw(:try);

sub test_Client_getRepositories : Test(3) {
  my $this = shift;

  my $client = $this->getClient;
  my $repositories = $client->getRepositories;

  my $nrRepos = scalar(keys %$repositories);
  note("found $nrRepos repository(ies)");
  ok(scalar($nrRepos) > 0) or diag("can't find at least one repository");

  my ($repo) = (values %$repositories);
  my $info = $repo->getRepositoryInfo;

  # SMELL: what's the absolute minimum?
  foreach my $key (qw(repositoryName repositoryId)) {
    note("$key=$info->{$key}");
    ok(defined $info->{$key});
  }
}

sub test_Client_getDefaultRepository : Test(2) {
  my $this = shift;

  my $repo = $this->getRepository;

  ok(defined $repo) or diag("can't find default repository");
  isa_ok($repo, "WebService::Cmis::Repository");
}

1;

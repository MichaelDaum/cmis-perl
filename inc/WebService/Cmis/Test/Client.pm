package WebService::Cmis::Test::Client;
use base qw(WebService::Cmis::Test);
use Test::More;

use strict;
use warnings;

use Error qw(:try);
use WebService::Cmis::ClientException ();

sub test_login : Test(1) {
  my $this = shift;

  my $client = $this->getClient;

  ok($client->{ticket} || !defined($client->{loginUrl}));
}

sub test_reuse_ticket : Test(2) {
  my $this = shift;
    
  my $client1 = $this->getClient;
  my $ticket1 = $client1->{ticket};

  SKIP: {
    skip "no ticket authentication", 2 unless $ticket1;

    my $client2 = $this->getClient()->login(ticket=>$ticket1);
    my $ticket2 = $client2->{ticket};

    ok($ticket2);

    is($ticket1, $ticket2);
  }
}

sub test_cant_reuse_after_logout : Test(1) {
  my $this = shift;

  my $client = $this->getClient;

  $client->logout;
  $this->{client} = undef;

  my $error = 0;
  try {
    $client->getRepositories;
  } catch WebService::Cmis::ClientException with {
    $error = 1;
    note("it is okay to get a ".shift);
  };

  ok($error, "we should not be able to use the client after having logged out");
}

sub test_logout : Test(2) {
  my $this = shift;

  my $client = $this->getClient;

  ok($client->{ticket} || !defined($client->{logoutUrl}));

  $client->logout;
  $this->{client} = undef;

  ok(!defined $client->{ticket} || !defined($client->{logoutUrl}));
}

sub test_Client_getRepositories : Test(3) {
  my $this = shift;

  my $client = $this->getClient;
  my $repositories = $client->getRepositories;

  my $nrRepos = scalar(keys %$repositories);
  note("found $nrRepos repository(ies)");
  ok(scalar($nrRepos) > 0) or diag("can't find at least one repository");

  my ($repo) = (values %$repositories);
  my $info = $repo->getRepositoryInfo;

  note("available info: ".join(", ", keys %$info));

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

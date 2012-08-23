package WebService::Cmis::Test::ACL;
use base qw(WebService::Cmis::Test);

use strict;
use warnings;

use Test::More;
use Error qw(:try);
use WebService::Cmis qw(:collections :utils :relations :namespaces :contenttypes);
use WebService::Cmis::ACL;

use XML::LibXML qw(:libxml);

sub test_ACL_getXmlDoc : Test {
  my $this = shift;

  my $origString = <<'HERE';
<?xml version="1.0" encoding="UTF-8"?>
<cmis:acl xmlns:cmis="http://docs.oasis-open.org/ns/cmis/core/200908/">
  <cmis:permission>
    <cmis:principal>
      <cmis:principalId>jdoe</cmis:principalId>
    </cmis:principal>
    <cmis:direct>false</cmis:direct>
    <cmis:permission>cmis:read</cmis:permission>
  </cmis:permission>
  <cmis:permission>
    <cmis:principal>
      <cmis:principalId>jdoe</cmis:principalId>
    </cmis:principal>
    <cmis:direct>false</cmis:direct>
    <cmis:permission>cmis:write</cmis:permission>
  </cmis:permission>
</cmis:acl>
HERE

  my $xmlDoc = XML::LibXML->load_xml(string => $origString);

  my $acl = new WebService::Cmis::ACL(xmlDoc=>$xmlDoc);
  my $newString = $acl->getXmlDoc->toString(1);

  note("orig:\n$origString");
  note("new:\n$newString\n");

  is($origString, $newString);
}

sub test_ACL_empty : Test(4) {
  my $this = shift;

  my $acl = new WebService::Cmis::ACL();
  ok(defined $acl);
  isa_ok($acl, 'WebService::Cmis::ACL');

  is(scalar($acl->getEntries), 0);
  ok(!defined $acl->{xmlDoc});
}

sub test_ACL_addEntry : Test(3) {
  my $this = shift;

  my $writeAccess = new WebService::Cmis::ACE(
    principalId => 'jdoe',
    direct => 'true',
    permissions => 'cmis:write'
  );

  my $readAccess = new WebService::Cmis::ACE(
    principalId => 'jdoe',
    direct => 'true',
    permissions => 'cmis:read'
  );

  my $acl = new WebService::Cmis::ACL();

  $acl->addEntry($writeAccess);
  $acl->addEntry($readAccess);
  is(scalar(@{$acl->{entries}}), 2);

  my $string = $acl->getXmlDoc->toString(1);
  ok(defined $string);

  my $expected = <<'HERE';
<?xml version="1.0" encoding="UTF-8"?>
<cmis:acl xmlns:cmis="http://docs.oasis-open.org/ns/cmis/core/200908/">
  <cmis:permission>
    <cmis:principal>
      <cmis:principalId>jdoe</cmis:principalId>
    </cmis:principal>
    <cmis:direct>true</cmis:direct>
    <cmis:permission>cmis:write</cmis:permission>
  </cmis:permission>
  <cmis:permission>
    <cmis:principal>
      <cmis:principalId>jdoe</cmis:principalId>
    </cmis:principal>
    <cmis:direct>true</cmis:direct>
    <cmis:permission>cmis:read</cmis:permission>
  </cmis:permission>
</cmis:acl>
HERE

  is($string, $expected);

}

sub test_ACL_removeEntry : Test(5) {
  my $this = shift;

  my $writeAccess = new WebService::Cmis::ACE(
    principalId => 'jdoe',
    direct => 'true',
    permissions => 'cmis:write'
  );

  my $readAccess = new WebService::Cmis::ACE(
    principalId => 'jdoe',
    direct => 'true',
    permissions => 'cmis:read'
  );

  my $acl = new WebService::Cmis::ACL();

  $acl->addEntry($writeAccess);
  note("1: acl=\n".$acl->toString);
  is(scalar(@{$acl->{entries}}), 1);

  $acl->addEntry($readAccess);
  note("2: acl=\n".$acl->toString);
  is(scalar(@{$acl->{entries}}), 2);

  $acl->removeEntry($writeAccess);
  note("3:acl=\n".$acl->toString);
  is(scalar(@{$acl->{entries}}), 1);

  $acl->addEntry($writeAccess);
  is(scalar(@{$acl->{entries}}), 2);

  $acl->removeEntry("jdoe");
  is(scalar(@{$acl->{entries}}), 0);
}

1;

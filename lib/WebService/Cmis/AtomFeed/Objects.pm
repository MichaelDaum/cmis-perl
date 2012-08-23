package WebService::Cmis::AtomFeed::Objects;

=head1 NAME

WebService::Cmis::AtomFeed::Objects

=head1 SYNOPSIS

This is a Result sets representing an atom feed of CMIS Objects.

=head1 DESCRIPTION

=cut

use strict;
use warnings;
use WebService::Cmis::AtomFeed ();
use WebService::Cmis::Object ();

our @ISA = qw(WebService::Cmis::AtomFeed);

=head1 METHODS

=over 4

=item newEntry(xmlDoc) -> $object

returns a CMIS Object created by parsing the given XML fragment

=cut

sub newEntry {
  my ($this, $xmlDoc) = @_;

  #print STDERR "### creating Obect from\n".$xmlDoc->toString(1)."\n###\n";
  return unless defined $xmlDoc;
  return new WebService::Cmis::Object::(repository=>$this->{repository}, xmlDoc=>$xmlDoc);
}

=back

=head1 COPYRIGHT AND LICENSE

Copyright 2012 Michael Daum

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See F<http://dev.perl.org/licenses/artistic.html>.

=cut

1;

package WebService::Cmis::ClientException;

=head1 NAME

WebService::Cmis::ClientException

=head1 SYNOPSIS


=head1 DESCRIPTION

=cut

use strict;
use warnings;
use Error ();
our @ISA = qw(Error);

=head1 METHODS

=over 4

=item new()

=cut

sub new {
  my ($class, $client) = @_;

  my $reason = $client->responseStatusLine;
  my $url = $client->responseBase;

  return $class->SUPER::new(-text=>"$reason at $url");
}

=back

=head1 AUTHOR

Michael Daum C<< <daum@michaeldaumconsulting.com> >>

=head1 COPYRIGHT AND LICENSE

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See L<perlartistic>.

=cut

1;



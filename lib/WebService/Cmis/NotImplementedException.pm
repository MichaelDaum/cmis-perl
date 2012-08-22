package WebService::Cmis::NotImplementedException;

=head1 NAME

WebService::Cmis::NotImplementedException

=head1 SYNOPSIS


=head1 DESCRIPTION

=cut

use strict;
use warnings;
use Error ();
our @ISA = qw(Error);

=head1 METHODS

=over 4

=item new

=cut

sub new {
  my $class = shift;

  my ($package, $filename, $line, $subroutine) = caller(1);

  return $class->SUPER::new(-text=>($subroutine||'')." not implemented yet.\n");
}

=back

=head1 AUTHOR

Michael Daum C<< <daum@michaeldaumconsulting.com> >>

=head1 COPYRIGHT AND LICENSE

Copyright 2012 Michael Daum

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See L<perlartistic>.

=cut

1;




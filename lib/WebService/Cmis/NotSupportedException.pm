package WebService::Cmis::NotSupportedException;

=head1 NAME

WebService::Cmis::NotSupportedException

=head1 SYNOPSIS

this is a pure marker class

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
  my ($class, $text) = @_;

  return $class->SUPER::new(-text=>"$text");
}

=back

=head1 COPYRIGHT AND LICENSE

Copyright 2012 Michael Daum

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See L<perlartistic>.

=cut

1;

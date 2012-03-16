package WebService::Cmis::Property::Decimal;

=head1 NAME

WebService::Cmis::Property::Decimal

Representation of a propertyDecimal of a cmis object

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

use strict;
use warnings;
use WebService::Cmis::Property ();
use POSIX ();
our @ISA = qw(WebService::Cmis::Property);

=item parse($string) -> $decimal

convert the given string into a decimal

=cut

sub parse {
  return POSIX::strtod($_[1]||'');
}


=head1 AUTHOR

Michael Daum C<< <daum@michaeldaumconsulting.com> >>

=head1 COPYRIGHT AND LICENSE

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See L<perlartistic>.

=cut

1;

package WebService::Cmis::Relationship;

=head1 NAME

WebService::Cmis::Relationship

Representation of a cmis object

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

use strict;
use warnings;
use WebService::Cmis::Object ();
use Error qw(:try);
our @ISA = ('WebService::Cmis::Object');


=head1 METHODS

=over 4

=cut

=item getSource

TODO: This is not yet implemented.

=cut

sub getSource { throw WebService::Cmis::NotImplementedException; }

=item getSourceId

TODO: This is not yet implemented.

=cut

sub getSourceId { throw WebService::Cmis::NotImplementedException; }

=item getTarget

TODO: This is not yet implemented.

=cut

sub getTarget { throw WebService::Cmis::NotImplementedException; }

=item getTargetId

TODO: This is not yet implemented.

=cut

sub getTargetId { throw WebService::Cmis::NotImplementedException; }

=back

=head1 AUTHOR

Michael Daum C<< <daum@michaeldaumconsulting.com> >>

=head1 COPYRIGHT AND LICENSE

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See L<perlartistic>.

=cut

1;



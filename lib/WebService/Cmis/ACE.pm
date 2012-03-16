package WebService::Cmis::ACE;

=head1 NAME

WebService::Cmis::ACE

Representation of a cmis ACE object

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

use strict;
use warnings;

=head1 METHODS

=over 4

=item new(I<%args>)

=cut

sub new {
  my $class = shift;

  my $this = bless({ @_ }, $class);

  unless (ref($this->{permissions})) {
    $this->{permission} = [$this->{permissions}];
  }

  return $this;
}

=item toString()

return a string representation of this object

=cut

sub toString {
  my $this = shift;

  my $result = $this->{principalId}." is allowed to ";
  $result .= $_ foreach @{$this->{permissions}};
  $result .= " (direct=".$this->{direct}.")";
}

=back

=head1 AUTHOR

Michael Daum C<< <daum@michaeldaumconsulting.com> >>

=head1 COPYRIGHT AND LICENSE

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See L<perlartistic>.

=cut

1;

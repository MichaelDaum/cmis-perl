package WebService::Cmis::AtomEntry;

=head1 NAME

WebService::Cmis::AtomEntry - Representation of a cmis object

=head1 DESCRIPTION

Base class for entries in a L<atom feed|WebService::Cmis::AtomFeeed>.

Sub classes:

=cut

use strict;
use warnings;
use WebService::Cmis qw(:namespaces :relations);
use XML::LibXML qw(:libxml);

our $CMIS_XPATH_TITLE = new XML::LibXML::XPathExpression('./*[local-name() = "title" and namespace-uri() ="'.ATOM_NS.'"]');
our $CMIS_XPATH_UPDATED = new XML::LibXML::XPathExpression('./*[local-name() = "updated" and namespace-uri() ="'.ATOM_NS.'"]');
our $CMIS_XPATH_SUMMARY = new XML::LibXML::XPathExpression('./*[local-name() = "summary" and namespace-uri() ="'.ATOM_NS.'"]');
our $CMIS_XPATH_PUBLISHED = new XML::LibXML::XPathExpression('./*[local-name() = "published" and namespace-uri() ="'.ATOM_NS.'"]');
our $CMIS_XPATH_AUTHOR = new XML::LibXML::XPathExpression('./*[local-name() = "author" and namespace-uri() ="'.ATOM_NS.'"]');
our $CMIS_XPATH_ID = new XML::LibXML::XPathExpression('./*[local-name() = "id" and namespace-uri() ="'.ATOM_NS.'"]');

=head1 METHODS

=over 4

=item new()

=cut

sub new {
  my $class = shift;

  my $this = bless({ @_ }, $class);
  $this->_initData;
  return $this;
}

=item _initData

resets the internal cache of this entry.

=cut

sub _initData {
  my $this = shift;

  undef $this->{name};
  undef $this->{summary};
  undef $this->{title};
  undef $this->{published};
  undef $this->{updated};
  undef $this->{author};
}

=item reload

a plain AtomEntry has got no way to reload itself. that's only possible for
cmis objects comping from a repository. 

=cut

sub reload {}

=item _xmlDoc

internal helper to make sure the xmlDoc is loaded.
don't use on plain AtomEntries without providing an xmlDoc to the constructor

=cut

sub _xmlDoc {
  my $this = shift;

  $this->reload unless defined $this->{xmlDoc};

  unless (defined $this->{xmlDoc}) {
    throw Error::Simple("Can't fetch xmlDoc, even though I tried to reload() this $this");
  }

  return $this->{xmlDoc};
}

=item _getDocumentElement -> $xmlNode

returns the document element of the current xmlDoc or the xmlDoc
itself if this object is constructed using an element instead of a complete document.

=cut

sub _getDocumentElement {
  my $xmlDoc = $_[0]->_xmlDoc;
  return ($xmlDoc && $xmlDoc->isa("XML::LibXML::Document"))?$xmlDoc->documentElement:$xmlDoc;
}

=item toString()

return a string representation of this object

=cut

sub toString {
  return $_[0]->getId;
}

=item getId

returns the unique ID of the change entry.

=cut

sub getId {
  my $this = shift;

  unless (defined $this->{id}) {
    $this->{id} = $this->{xmlDoc}->findvalue($CMIS_XPATH_ID);
  }

  return $this->{id};
}


=item getTitle -> $title

returns the value of the object's atom:title property.

=cut

sub getTitle {
  my $this = shift;

  unless (defined $this->{title}) {
    $this->{title} = $this->_getDocumentElement->findvalue($CMIS_XPATH_TITLE);
  }

  return $this->{title};
}

=item getSummary -> $summary

returns the value of the object's atom:summary property.

=cut

sub getSummary {
  my $this = shift;

  unless ($this->{summary}) {
    $this->{summary} = $this->_getDocumentElement->findvalue($CMIS_XPATH_SUMMARY);
  }

  return $this->{summary};
}

=item getUpdated -> $epoch

returns the value of the object's atom:updated property.

=cut

sub getUpdated {
  my $this = shift;

  unless ($this->{updated}) {
    require WebService::Cmis::Property;
    $this->{updated} = WebService::Cmis::Property::parseDateTime($this->_getDocumentElement->findvalue($CMIS_XPATH_UPDATED));
  }

  return $this->{updated};
}

=item getPublished -> $epoch

returns the value of the object's atom:published property.

=cut

sub getPublished {
  my $this = shift;

  unless ($this->{published}) {
    require WebService::Cmis::Property;
    $this->{published} = WebService::Cmis::Property::parseDateTime($this->_getDocumentElement->findvalue($CMIS_XPATH_PUBLISHED));
  }

  return $this->{published};
}

=item getAuthor -> $author

returns the value of the object's atom:author property.

=cut

sub getAuthor {
  my $this = shift;

  unless ($this->{author}) {
    $this->{author} = $this->_getDocumentElement->findvalue($CMIS_XPATH_AUTHOR);
  }

  return $this->{author};
}

=item getLink($relation, $linkType) -> $href

returns the href attribute of an Atom link element for the
specified relation.

=cut

sub getLink {
  my ($this, $relation, $linkType) = @_;

  $relation = '*' unless defined $relation;

  my $selector = $relation eq '*'?
    './*[local-name() = "link" and namespace-uri() = "'.ATOM_NS.'"]':
    './*[local-name() = "link" and namespace-uri() = "'.ATOM_NS.'" and @rel="'.$relation.'"]';

  my @nodes = $this->_getDocumentElement->findnodes($selector);

  foreach my $linkElement (@nodes) {
    my $attrs = $linkElement->attributes;

    if (defined $linkType) {
      my $type = $attrs->getNamedItem('type');
      next unless $type && $type->value =~ /$linkType/;
    }
    my $href = $attrs->getNamedItem('href')->value;
    return $href;
  }

  return;
}


=back

=head1 AUTHOR

Michael Daum C<< <daum@michaeldaumconsulting.com> >>

=head1 COPYRIGHT AND LICENSE

Copyright 2012 Michael Daum

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.  See F<http://dev.perl.org/licenses/artistic.html>.

=cut

1;

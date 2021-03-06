package App::Notitia::Role::RSS;

use namespace::autoclean;

use App::Notitia::Util     qw( iterator loc mtime );
use Class::Usul::Constants qw( EXCEPTION_CLASS NUL TRUE );
use Class::Usul::Functions qw( create_token throw );
use Class::Usul::Time      qw( time2str );
use Class::Usul::Types     qw( HashRef NonEmptySimpleStr
                               NonZeroPositiveInt Object Str );
use HTTP::Status           qw( HTTP_OK HTTP_NOT_FOUND );
use Moo::Role;

requires qw( base_uri config initialise_page localised_tree );

has 'feed_subtitle'    => is => 'ro', isa => Str, default => NUL;

has 'feed_title'       => is => 'ro', isa => Str, default => NUL;

has 'formatters'       => is => 'ro', isa => HashRef[Object],
   builder             => sub { {} };

has 'max_feed_chars'   => is => 'ro', isa => NonZeroPositiveInt, default => 500;

has 'max_feed_entries' => is => 'ro', isa => NonZeroPositiveInt, default => 10;

has 'max_feed_lines'   => is => 'ro', isa => NonZeroPositiveInt, default => 5;

# Construction
around 'BUILDARGS' => sub {
   my ($orig, $self, @args) = @_; my $attr = $orig->( $self, @args );

   my $views = $attr->{views} or return $attr;

   exists $views->{html} and $attr->{formatters}
        = $views->{html}->can( 'formatters' ) ? $views->{html}->formatters : {};

   return $attr;
};

# Private methods
my $_filter_content = sub {
   my $self      = shift;
   my $max_chars = $self->max_feed_chars;
   my $max_lines = $self->max_feed_lines;

   return sub {
      my ($self, $src) = @_; my @lines = split m{ \n }mx, $src, $max_lines + 1;

      @lines > $max_lines and pop @lines;

      return (substr join( "\n", @lines), 0, $max_chars - 3).'...';
   }
};

my $_format_page = sub {
   my ($self, $req, $page) = @_;

   my $content = $page->{content}; my $formatter;

   $page->{format} and $formatter = $self->formatters->{ $page->{format} };

   $formatter and $page->{filter} = $_filter_content->( $self )
              and $content = $formatter->serialize( $req, $page );

   my $author = $page->{author} // 'admin';
   my $person = $self->components->{person}->find_by_shortcode( $author );
   my $email  = $person ? $person->email_address : "${author}\@example.com";
   my $label  = $person ? $person->label : $author;

   return {
      author     => "${email} (${label})",
      categories => $page->{categories} // [],
      content    => $content,
      created    => time2str( '%Y-%m-%dT%XZ', $page->{created} ),
      guid       => substr( create_token( $page->{url} ), 0, 32 ),
      modified   => time2str( '%Y-%m-%dT%XZ', $page->{modified} ),
      link       => $self->base_uri( $req, [ $page->{url} ] ),
      title      => loc( $req, $page->{title} ), };
};

# Public methods
sub get_rss_feed {
   my ($self, $req) = @_; my $locale = $req->locale;

   my $tree = $self->localised_tree( $locale ) or throw
      'Locale [_1] has no document tree', [ $locale ], rv => HTTP_NOT_FOUND;
   my $iter = iterator $tree;

   my @tuples; while (defined( my $node = $iter->() )) {
      $node->{type} eq 'file' and $node->{id} ne 'index'
         and push @tuples, [ $node->{modified}, $node ];
   }

   my @entries;

   for my $node (map { $_->[ 1 ] } sort { $b->[ 0 ] <=> $a->[ 0 ] } @tuples) {
      my $page = $self->initialise_page( $req, $node, $locale );

      push @entries, $self->$_format_page( $req, $page );
      @entries >= $self->max_feed_entries and last;
   }

  (my $lang = lc $locale) =~ s{ [_] }{-}mx;

   return {
      code        => HTTP_OK,
      page        => {
         built    => time2str( '%a, %d %b %Y %X %Z', mtime( $tree ), 'GMT' ),
         entries  => [ @entries ],
         language => $lang,
         link     => $self->base_uri( $req ),
         pubdate  => time2str( '%a, %d %b %Y %X %Z', time, 'GMT' ),
         subtitle => loc( $req, $self->feed_subtitle ),
         title    => loc( $req, $self->feed_title ), },
      view        => 'rss', };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Role::RSS - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Role::RSS;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=head1 Diagnostics

=head1 Dependencies

=over 3

=item L<Class::Usul>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module. Please report problems to
http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Notitia.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 Author

Peter Flanigan, C<< <pjfl@cpan.org> >>

=head1 License and Copyright

Copyright (c) 2016 Peter Flanigan. All rights reserved

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE

=cut

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:

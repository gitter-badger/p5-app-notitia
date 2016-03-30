package App::Notitia::Config;

use namespace::autoclean;

use Class::Usul::Constants       qw( FALSE NUL TRUE );
use Class::Usul::Crypt::Util     qw( decrypt_from_config encrypt_for_config );
use Class::Usul::File;
use Class::Usul::Functions       qw( class2appdir create_token );
use Data::Validation::Constants  qw( );
use DateTime::TimeZone           qw( );
use File::DataClass::Types       qw( ArrayRef Bool CodeRef Directory File
                                     HashRef NonEmptySimpleStr
                                     NonNumericSimpleStr
                                     NonZeroPositiveInt Object Path
                                     PositiveInt SimpleStr Str Undef );
use Moo;

extends q(Class::Usul::Config::Programs);

# Private functions
my $_to_array_of_hash = sub {
   my ($href, $key_key, $val_key) = @_;

   return [ map { my $v = $href->{ $_ }; +{ $key_key => $_, $val_key => $v } }
            sort keys %{ $href } ],
};

# Attribute constructors
my $_build_cdnjs = sub {
   my $self  = shift;
   my %cdnjs = map { $_->[ 0 ] => $self->cdn.$_->[ 1 ] } @{ $self->jslibs };

   return \%cdnjs;
};

my $_build_components = sub {
   my $self = shift; my $conf = {};

   for my $name (keys %{ $self->_components } ) {
      for my $k (keys %{ $self->_components->{ $name } }) {
         $conf->{ $name }->{ $k } = $self->_components->{ $name }->{ $k };
      }
   }

   return $conf;
};

my $_build_links = sub {
   return $_to_array_of_hash->( $_[ 0 ]->_links, 'name', 'url' );
};

my $_build_secret = sub {
   my $self = shift; my $file = $self->ctlfile; my $data = {}; my $token;

   if ($file->exists) {
      $data  = Class::Usul::File->data_load( paths => [ $file ] ) // {};
      $token = decrypt_from_config $self, $data->{secret};
   }

   unless ($token) {
      $data->{secret} = encrypt_for_config $self, $token = create_token;
      Class::Usul::File->data_dump( { path => $file->assert, data => $data } );
   }

   return $token;
};

my $_build_user_home = sub {
   my $appldir = $_[ 0 ]->appldir; my $verdir = $appldir->basename;

   return $verdir =~ m{ \A v \d+ \. \d+ p (\d+) \z }msx
        ? $appldir->dirname : $appldir;
};

sub _build_l10n_domains {
   my $prefix = $_[ 0 ]->prefix; return [ $prefix, "${prefix}-".$_[ 0 ]->name ];
}

# Public attributes
has 'assetdir'        => is => 'lazy', isa => Path, coerce => TRUE,
   builder            => sub { $_[ 0 ]->docs_root->catdir( $_[ 0 ]->assets ) };

has 'assets'          => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'assets',

has 'cdn'             => is => 'ro',   isa => SimpleStr, default => NUL;

has 'cdnjs'           => is => 'lazy', isa => HashRef,
   builder            => $_build_cdnjs, init_arg => undef;

has 'components'      => is => 'lazy', isa => HashRef,
   builder            => $_build_components, init_arg => undef;

has 'compress_css'    => is => 'ro',   isa => Bool, default => TRUE;

has 'connect_params'  => is => 'ro',   isa => HashRef,
   builder            => sub { { quote_names => TRUE } };

has 'css'             => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'css';

has 'database'        => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'schedule';

has 'default_route'   => is => 'lazy', isa => NonEmptySimpleStr,
   builder            => sub {
      (my $mp = $_[ 0 ]->mount_point) =~ s{ \A / \z }{}mx; "${mp}/index" };

has 'default_view'    => is => 'ro',   isa => SimpleStr, default => 'html';

has 'deflate_types'   => is => 'ro',   isa => ArrayRef[NonEmptySimpleStr],
   builder            => sub {
      [ qw( text/css text/html text/javascript application/javascript ) ] };

has 'description'     => is => 'ro',   isa => SimpleStr, default => NUL;

has 'docs_mtime'      => is => 'lazy', isa => Path, coerce => TRUE,
   builder            => sub { $_[ 0 ]->docs_root->catfile( '.mtime' ) };

has 'docs_root'       => is => 'lazy', isa => Directory, coerce => TRUE,
   builder            => sub { $_[ 0 ]->root->catdir( 'docs' ) };

has 'drafts'          => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'drafts';

has 'extensions'      => is => 'ro',   isa => HashRef[ArrayRef],
   builder            => sub { { markdown => [ qw( md mkdn ) ] } };

has 'images'          => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'img';

has 'js'              => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'js';

has 'jslibs'          => is => 'ro',   isa => ArrayRef, builder => sub { [] };

has 'keywords'        => is => 'ro',   isa => SimpleStr, default => NUL;

has 'layout'          => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'standard';

has 'less'            => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'less';

has 'less_files'      => is => 'ro',   isa => ArrayRef[NonEmptySimpleStr],
   builder            => sub { [ qw( yellow ) ] };

has 'links'           => is => 'lazy', isa => ArrayRef[HashRef],
   builder            => $_build_links, init_arg => undef;

has 'load_factor'     => is => 'ro',   isa => NonZeroPositiveInt,
   default            => 14;

has 'max_asset_size'  => is => 'ro',   isa => PositiveInt, default => 4_194_304;

has 'max_messages'    => is => 'ro',   isa => NonZeroPositiveInt, default => 3;

has 'max_sess_time'   => is => 'ro',   isa => PositiveInt, default => 3_600;

has 'mdn_tab_width'   => is => 'ro',   isa => NonZeroPositiveInt, default => 3;

has 'min_id_length'   => is => 'ro',   isa => PositiveInt, default => 3;

has 'min_name_length' => is => 'ro',   isa => PositiveInt, default => 5;

has 'mount_point'     => is => 'ro',   isa => NonEmptySimpleStr,
   default            => '/notitia';

has 'no_index'        => is => 'ro',   isa => ArrayRef[NonEmptySimpleStr],
   builder            => sub {
      [ qw( \.git$ \.htpasswd$ \.json$ \.mtime$ \.svn$ assets$ posts$ ) ] };

has 'no_user_email'   => is => 'ro',   isa => Bool, default => FALSE;

has 'owner'           => is => 'lazy', isa => NonEmptySimpleStr,
   builder            => sub { $_[ 0 ]->prefix };

has 'person_prefix'   => is => 'ro',   isa => SimpleStr, default => NUL;

has 'port'            => is => 'lazy', isa => NonZeroPositiveInt,
   default            => 8085;

has 'posts'           => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'posts';

has 'repo_url'        => is => 'ro',   isa => SimpleStr, default => NUL;

has 'request_roles'   => is => 'ro',   isa => ArrayRef[NonEmptySimpleStr],
   builder            => sub { [ 'L10N', 'Session', 'JSON', 'Cookie' ] };

has 'schema_classes'  => is => 'ro',   isa => HashRef[NonEmptySimpleStr],
   builder            => sub { {
      'schedule'      => 'App::Notitia::Schema::Schedule', } };

has 'scrubber'        => is => 'ro',   isa => Str,
   default            => '[^ !\"#%&\'\(\)\*\+\,\-\./0-9:;=\?@A-Z\[\]_a-z\|\~]';

has 'secret'          => is => 'lazy', isa => NonEmptySimpleStr,
   builder            => $_build_secret;

has 'serve_as_static' => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'css | favicon.ico | fonts | img | js | less';

has 'server'          => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'FCGI';

has 'session_attr'    => is => 'lazy', isa => HashRef[ArrayRef],
   builder            => sub { {
      first_name      => [ SimpleStr | Undef                ],
      query           => [ SimpleStr | Undef                ],
      skin            => [ NonEmptySimpleStr, $_[ 0 ]->skin ],
      theme           => [ NonEmptySimpleStr, 'yellow'      ],
      wanted          => [ SimpleStr | Undef                ], } };

has 'skin'            => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'hyde';

has 'slot_certs'      => is => 'ro',   isa => ArrayRef[NonEmptySimpleStr],
   builder            => sub { [ 'catagory_b' ] };

has 'slot_limits'     => is => 'ro',   isa => ArrayRef[PositiveInt],
   builder            => sub { [ 2, 1, 3, 3, 1, 1 ] };

has 'stash_attr'      => is => 'lazy', isa => HashRef[ArrayRef],
   builder            => sub { {
      config          => [ qw( description keywords ) ],
      links           => [ qw( assets css images js ) ],
      request         => [ qw( authenticated host language locale username ) ],
      session         => [ sort keys %{ $_[ 0 ]->session_attr } ], } };

has 'time_zone'       => is => 'lazy', isa => CodeRef,
   builder            => sub { sub {
      DateTime::TimeZone->new( name => 'local' ) } };

has 'title'           => is => 'ro',   isa => NonEmptySimpleStr,
   default            => 'Notitia';

has 'user'            => is => 'ro',   isa => SimpleStr, default => NUL;

has 'user_home'       => is => 'lazy', isa => Path, coerce => TRUE,
   builder            => $_build_user_home;

has 'workers'         => is => 'ro',   isa => NonZeroPositiveInt, default => 5;

# Private attributes
has '_components'     => is => 'ro',   isa => HashRef,
   builder            => sub { {} }, init_arg => 'components';

has '_links'          => is => 'ro',   isa => HashRef,
   builder            => sub { {} }, init_arg => 'links';

# Attribute constructors
sub _build_ctlfile {
   my $name      = class2appdir $_[ 0 ]->inflate_symbol( $_[ 1 ], 'appclass' );
   my $extension = $_[ 0 ]->inflate_symbol( $_[ 1 ], 'extension' );

   return $_[ 0 ]->inflate_path( $_[ 1 ], 'ctrldir', $name.$extension );
}

sub _build__l10n_attributes {
   return { gettext_catagory => NUL, };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Config - Defines the configuration file options and their defaults

=head1 Synopsis

   use Class::Usul;

   my $usul   = Class::Usul->new( config_class => 'App::Notitia::Config' );
   my $vardir = $usul->config->vardir;

=head1 Description

Each of the attributes defined here, plus the ones inherited from
L<Class::Usul::Config>, can have their default value overridden
by the value in the configuration file

=head1 Configuration and Environment

The configuration file is, by default, in JSON format

It is found by calling the L<find_apphome|Class::Usul::Functions/find_apphome>
function

Defines the following attributes;

=over 3

=item C<assetdir>

Defaults to F<var/root/docs/assets>. Path object for the directory
containing user uploaded files

=item C<assets>

A non empty simple string that defaults to F<assets>. Relative URI
that locates the asset files uploaded by users

=item C<cdn>

A simple string containing the URI prefix for the content delivery network.
Defaults to null. This needs to set in the configuration file otherwise
the JavaScript libraries used by this application will not be found

=item C<cdnjs>

A hash reference of URIs for JavaScript libraries stored on the
content delivery network. Created prepending L</cdn> to each of the
L</jslibs> values

=item C<components>

A hash reference containing component specific configuration options. Keyed
by component classname with the leading application class removed. e.g.

   $self->config->components->{ 'Controller::Root' };

Defines attributes for these components;

=over 3

=item C<Model::Posts>

Defines these attributes;

=over 3

=item C<feed_subtitle>

The RSS event feed subtitle

=item C<feed_title>

The RSS event feed title

=back

=back

=item C<compress_css>

Boolean default to true. Should the command line C<make-css> method compress
it's output

=item C<connect_params>

A hash reference which defaults to C<< { quote_names => TRUE } >>. These
are extra connection parameters passed to the database

=item C<css>

A non empty simple string that defaults to F<css>. Relative URI that locates
the static CSS files

=item C<database>

A non empty simple string which defaults to C<schedule>.

=item C<default_route>

A non empty simple string that defaults to F</notitia/index> assuming that the
L</mount_point> is F</notitia>. What to redirect to for all paths outside the
mount point

=item C<default_view>

Simple string that defaults to C<html>. The moniker of the view that will be
used by default to render the response

=item C<deflate_types>

An array reference of non empty simple strings. The list of mime types to
deflate in L<Plack> middleware

=item C<description>

A simple string that defaults to null. The HTML meta attributes description
value

=item C<docs_mtime>

Path object for the document tree modification time file. The indexing program
touches this file setting it to modification time of the most recently changed
file in the document tree

=item C<docs_root>

The project's document root.  A lazily evaluated directory that defaults to
F<var/root/docs>. The document root for the microformat content pages

=item C<drafts>

A non empty simple string. Prepended to the pathname of files created in
draft mode. Draft mode files are ignored by the static site generator

=item C<extensions>

A hash reference. The keys are microformat names and the values are an
array reference of filename extensions that the corresponding view can
render

=item C<images>

A non empty simple string that defaults to F<img>. Relative URI that
locates the static image files

=item C<js>

A non empty simple string that defaults to F<js>. Relative URI that
locates the static JavaScript files

=item C<jslibs>

An array reference of tuples. The first element is the library name, the second
is a partial URI for a JavaScript library stored on the content delivery
network. Defaults to an empty list

=item C<keywords>

A simple string that defaults to null. The HTML meta attributes keyword
list value

=item C<layout>

A non empty simple string that defaults to F<standard>. The name of the
L<Template::Toolkit> template used to render the HTML response page. The
template will be wrapped by F<wrapper.tt>

=item C<less>

A non empty simple string that defaults to F<less>. Relative URI that
locates the static Less files

=item C<less_files>

The list of predefined colour schemes and feature specific less files

=item C<links>

A lazily evaluated array reference of hashes created automatically from the
hash reference in the configuration file. Each hash has a single
key / value pair, the link name and it's URI

=item C<load_factor>

Defaults to 14. A non zero positive integer passed to the C<bcrypt> function

=item C<max_asset_size>

Integer defaults to 4Mb. Maximum size in bytes of the file upload

=item C<max_messages>

Non zero positive integer defaults to 3. The maximum number of messages to
store in the session between requests

=item C<max_sess_time>

Time in seconds before a session expires. Defaults to 15 minutes

=item C<mdn_tab_width>

Non zero positive integer defaults to 3. The number of spaces required to
indent a code block in the markdown class

=item C<min_id_length>

The length of the automatically generated user names. Defaults to three
characters

=item C<min_name_length>

The minimum length of a person name (last name plus first name). The
automatic user name generator will refuse to operate on fewer characters
than this. Defaults to five characters

=item C<mount_point>

A non empty simple string that defaults to F</notitia>. The root of the URI on
which the application is mounted

=item C<no_index>

An array reference that defaults to C<[ .git .svn cgi-bin  ]>.
List of files and directories under the document root to ignore

=item C<no_user_email>

Suppress the sending of user activation emails. Used in development only

=item C<owner>

A non empty simple string that defaults to the configuration C<prefix>
attribute. Name of the user and group that should own all files and
directories in the application when installed

=item C<person_prefix>

This non empty simple string must be set in the configuration file for
the automatic user name generator to work. It is the "sphere of authority"
prefix which is prepended to the shortcodes created by the generator. This
should be a unique value for each installation of this application

=item C<port>

A lazily evaluated non zero positive integer that defaults to 8085. This
is the port number that the application server will listen on if started
in production mode with a L<Plack> engine that listens on a port

=item C<posts>

A non empty simple string the defaults to F<posts>.  The directory
name where dated markdown files are created in category
directories. These are the blogs posts or news articles

=item C<repo_url>

A simple string that defaults to null. The URI of the source code repository
for this project

=item C<request_roles>

Defaults to C<L10N>, C<Session>, C<JSON>, and C<Cookie>. The list of roles to
apply to the default request base class

=item C<schema_classes>

A hash reference of non empty simple strings which defaults to
C<< { 'schedule' => 'App::MCP::Schema::Schedule' } >>. Maps database
names onto DBIC schema classes

=item C<scrubber>

A string used as a character class in a regular expression. These character
are scrubber from user input so they cannot appear in any user supplied
pathnames or query terms. Defaults to C<[;\$\`&\r\n]>

=item C<serve_as_static>

A non empty simple string which defaults to
C<css | favicon.ico | img | js | less>. Selects the resources that are served
by L<Plack::Middleware::Static>

=item C<server>

A non empty simple string that defaults to C<FCGI>. The L<Plack> engine
name to load when the application server is started in production mode

=item C<session_attr>

A hash reference of array references. These attributes are added to the ones in
L<Web::ComposableRequest::Session> to created the session class. The hash key
is the attribute name and the tuple consists of a type and a optional default
value. The values of these attributes persist between requests. The default
list of attributes is;

=over 3

=item C<query>

Default search string

=item C<skin>

Name of the default skin. Defaults to C<hyde> which is derived from
Jekyll

=item C<theme>

A non empty simple string that defaults to C<yellow>. The name of the
default colour scheme

=back

=item C<skin>

A non empty simple string that defaults to C<hyde>. The name of the default
skin used to theme the appearance of the application

=item C<slot_certs>

An array reference of non empty simple strings. The list of certifications
a biker rider is required to have before being able to claim a slot in a
rota

=item C<slot_limits>

An array reference containing six integers. These are the limits on the number
of rota slots allowed for each type human resource. In order they are;
controllers day, controllers night, riders day, riders night, spare drivers
day, and spare drivers night

=item C<stash_attr>

A hash reference of array references. The keys indicate a data source and the
values are lists of attribute names. The values of the named attributes are
copied into the stash. Defines the following keys and values;

=over 3

=item C<config>

The list of configuration attributes whose values are copied to the C<page>
hash reference in the stash

=item C<links>

An array reference that defaults to
C<[ assets css images js ]>.  The application pre-calculates
URIs for these static directories for use in the HTML templates

=item C<request>

The list of request attributes whose values are copied to the C<page> hash
reference in the stash

=item C<session>

An array reference that defaults to the keys of the L</session_attr> hash
reference. List of attributes that can be specified as query parameters in
URIs. Their values are persisted between requests stored in the session store

=back

=item C<title>

A non empty simple string that defaults to C<Notitia>. The applcation's
title as displayed in the title bar of all pages

=item C<user>

Simple string that defaults to null. If set the daemon process will change
to running as this user when it forks into the background

=item C<user_home>

The home directory of the user who owns the files and directories in the
the application

=item C<workers>

A non zero positive integer. The number of processes to start when running
under a pre-forking server. Defaults to 5

=head1 Subroutines/Methods

None

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<Class::Usul::Config>

=item L<File::DataClass>

=item L<Moo>

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

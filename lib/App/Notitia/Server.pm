package App::Notitia::Server;

use namespace::autoclean;

use App::Notitia::Util     qw( authenticated_only enhance );
use Class::Usul;
use Class::Usul::Constants qw( NUL TRUE );
use Class::Usul::Functions qw( ensure_class_loaded );
use Class::Usul::Types     qw( HashRef Plinth );
use HTTP::Status           qw( HTTP_FOUND );
use Plack::Builder;
use Web::Simple;

# Private attributes
has '_config_attr' => is => 'ro',   isa => HashRef,
   builder         => sub { { name => 'server' } }, init_arg => 'config';

has '_usul'        => is => 'lazy', isa => Plinth,
   builder         => sub { Class::Usul->new( enhance $_[ 0 ]->_config_attr ) },
   handles         => [ 'config', 'debug', 'dumper', 'l10n', 'lock', 'log' ];

with 'Web::Components::Loader';

# Construction
around 'to_psgi_app' => sub {
   my ($orig, $self, @args) = @_; my $psgi_app = $orig->( $self, @args );

   my $conf = $self->config; my $assets = $conf->assets;

   my $serve_as_static = $conf->serve_as_static;

   return builder {
      enable 'ContentLength';
      enable 'FixMissingBodyInRedirect';
      enable 'ConditionalGET';
      mount $conf->mount_point => builder {
         enable 'Deflater',
            content_type => $conf->deflate_types, vary_user_agent => TRUE;
         enable 'Static',
            path => qr{ \A / (?: $serve_as_static ) }mx, root => $conf->root;
         enable 'Session::Cookie',
            expires     => 7_776_000,
            httponly    => TRUE,
            path        => $conf->mount_point,
            secret      => $conf->secret,
            session_key => $conf->prefix.'_session';
         enable 'Static',
            path => authenticated_only( $assets ), pass_through => TRUE,
            root => $conf->docs_root;
         enable 'LogDispatch', logger => $self->log;
         enable_if { $self->debug } 'Debug';
         $psgi_app;
      };
      mount '/' => builder {
         sub { [ HTTP_FOUND, [ 'Location', $conf->default_route ], [] ] }
      };
   };
};

sub BUILD {
   my $self   = shift;
   my $conf   = $self->config;
   my $server = ucfirst( $ENV{PLACK_ENV} // NUL );
   my $class  = $conf->appclass; ensure_class_loaded $class;
   my $port   = $class->env_var( 'port' );
   my $info   = 'v'.$class->VERSION; $port and $info .= " on port ${port}";

   $self->log->info( "${server} Server started ${info}" );

   return;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Server - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Server;
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

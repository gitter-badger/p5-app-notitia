package App::Notitia::Controller::Root;

use Web::Simple;

with q(Web::Components::Role);

has '+moniker' => default => 'root';

sub dispatch_request {
   sub (GET  + /admin             + ?*) { [ 'admin', 'index',           @_ ] },
   sub (GET  + /admin/index       + ?*) { [ 'admin', 'index',           @_ ] },
   sub (POST + /assets + *file~   + ?*) { [ 'docs',  'upload',          @_ ] },
   sub (GET  + /check_field       + ?*) { [ 'user',  'check_field',     @_ ] },
   sub (POST + /docs  | /docs/**  + ?*) { [ 'docs',  'from_request',    @_ ] },
   sub (GET  + /docs              + ?*) { [ 'docs',  'index',           @_ ] },
   sub (GET  + /docs/dialog       + ?*) { [ 'docs',  'dialog',          @_ ] },
   sub (GET  + /docs/search       + ?*) { [ 'docs',  'search',          @_ ] },
   sub (GET  + /docs/**           + ?*) { [ 'docs',  'page',            @_ ] },
   sub (GET  + /events            + ?*) { [ 'event', 'events',          @_ ] },
   sub (POST + /event | /event/*  + ?*) { [ 'event', 'from_request',    @_ ] },
   sub (GET  + /event | /event/*  + ?*) { [ 'event', 'event',           @_ ] },
   sub (GET  + /posts/dialog      + ?*) { [ 'posts', 'dialog',          @_ ] },
   sub (GET  + /posts/rss         + ?*) { [ 'posts', 'rss_feed',        @_ ] },
   sub (GET  + /posts | /posts/** + ?*) { [ 'posts', 'page',            @_ ] },
   sub (POST + /role/*            + ?*) { [ 'admin', 'from_request',    @_ ] },
   sub (GET  + /role/*            + ?*) { [ 'admin', 'role',            @_ ] },
   sub (GET  + /rota  | /rota/**  + ?*) { [ 'sched', 'day_rota',        @_ ] },
   sub (POST + /slot/**           + ?*) { [ 'sched', 'from_request',    @_ ] },
   sub (GET  + /slot/**           + ?*) { [ 'sched', 'slot',            @_ ] },
   sub (GET  + /user/activate/*   + ?*) { [ 'admin', 'activate',        @_ ] },
   sub (POST + /user/login        + ?*) { [ 'user',  'login_action',    @_ ] },
   sub (GET  + /user/login        + ?*) { [ 'user',  'login',           @_ ] },
   sub (POST + /user/logout       + ?*) { [ 'user',  'logout_action',   @_ ] },
   sub (POST + /user/password     + ?*) { [ 'user',  'from_request',    @_ ] },
   sub (GET  + /user/password     + ?*) { [ 'user',  'change_password', @_ ] },
   sub (GET  + /user/password/*   + ?*) { [ 'user',  'change_password', @_ ] },
   sub (POST + /user/profile      + ?*) { [ 'user',  'from_request',    @_ ] },
   sub (GET  + /user/profile      + ?*) { [ 'user',  'profile',         @_ ] },
   sub (POST + /user  | /user/*   + ?*) { [ 'admin', 'from_request',    @_ ] },
   sub (GET  + /user  | /user/*   + ?*) { [ 'admin', 'person',          @_ ] },
   sub (GET  + /users             + ?*) { [ 'admin', 'people',          @_ ] },
   sub (GET  + /vehicle           + ?*) { [ 'admin', 'vehicle',         @_ ] },
   sub (GET  + /vehicle/*         + ?*) { [ 'admin', 'vehicle',         @_ ] },
   sub (GET  + /index | /         + ?*) { [ 'user',  'index',           @_ ] },
   sub (GET  + /**                + ?*) { [ 'user',  'not_found',       @_ ] };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Controller::Root - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Controller::Root;
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
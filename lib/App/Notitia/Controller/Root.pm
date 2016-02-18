package App::Notitia::Controller::Root;

use Web::Simple;

with q(Web::Components::Role);

has '+moniker' => default => 'root';

sub dispatch_request {
   sub (POST + /admin  | /admin/*  + ?*) { [ 'admin', 'from_request', @_ ] },
   sub (GET  + /admin  | /admin/*  + ?*) { [ 'admin', 'get_content',  @_ ] },
   sub (GET  + /dialog             + ?*) { [ 'sched', 'get_dialog',   @_ ] },
   sub (POST + /login  | /logout   + ?*) { [ 'admin', 'from_request', @_ ] },
   sub (GET  + /help/  | /help/**  + ?*) { [ 'help',  'get_content',  @_ ] },
   sub (GET  + /rota   | /rota/**  + ?*) { [ 'sched', 'get_content',  @_ ] },
   sub (GET  + /rss                + ?*) { [ 'sched', 'get_rss_feed', @_ ] },
   sub (GET  + /search             + ?*) { [ 'sched', 'search',       @_ ] },
   sub (POST + /user   | /user/*   + ?*) { [ 'admin', 'from_request', @_ ] },
   sub (GET  + /user   | /user/*   + ?*) { [ 'admin', 'get_profile',  @_ ] },
   sub (POST + /       | /**       + ?*) { [ 'sched', 'from_request', @_ ] },
   sub (GET  + /       | /index    + ?*) { [ 'sched', 'index',        @_ ] },
   sub (GET  + /**                 + ?*) { [ 'sched', 'not_found',    @_ ] };
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

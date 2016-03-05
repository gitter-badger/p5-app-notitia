package App::Notitia::Controller::Main;

use Web::Simple;

with q(Web::Components::Role);

has '+moniker' => default => 'main';

sub dispatch_request {
   sub (GET  + /admin              + ?*) { [ 'admin', 'index',          @_ ] },
   sub (GET  + /admin/index        + ?*) { [ 'admin', 'index',          @_ ] },
   sub (POST + /certification/**   + ?*) { [ 'certs', 'from_request',   @_ ] },
   sub (GET  + /certification/**   + ?*) { [ 'certs', 'certification',  @_ ] },
   sub (GET  + /certifications/*   + ?*) { [ 'certs', 'certifications', @_ ] },
   sub (POST + /endorsement/**     + ?*) { [ 'blots', 'from_request',   @_ ] },
   sub (GET  + /endorsement/**     + ?*) { [ 'blots', 'endorsement',    @_ ] },
   sub (GET  + /endorsements/*     + ?*) { [ 'blots', 'endorsements',   @_ ] },
   sub (POST + /event | /event/*   + ?*) { [ 'event', 'from_request',   @_ ] },
   sub (GET  + /event | /event/*   + ?*) { [ 'event', 'event',          @_ ] },
   sub (GET  + /events             + ?*) { [ 'event', 'events',         @_ ] },
   sub (GET  + /person/activate/*  + ?*) { [ 'admin', 'activate',       @_ ] },
   sub (POST + /person | /person/* + ?*) { [ 'admin', 'from_request',   @_ ] },
   sub (GET  + /person | /person/* + ?*) { [ 'admin', 'person',         @_ ] },
   sub (GET  + /people             + ?*) { [ 'admin', 'people',         @_ ] },
   sub (POST + /role/*             + ?*) { [ 'role',  'from_request',   @_ ] },
   sub (GET  + /role/*             + ?*) { [ 'role',  'role',           @_ ] },
   sub (GET  + /rota  | /rota/**   + ?*) { [ 'sched', 'day_rota',       @_ ] },
   sub (POST + /slot/**            + ?*) { [ 'sched', 'from_request',   @_ ] },
   sub (GET  + /slot/**            + ?*) { [ 'sched', 'slot',           @_ ] },
   sub (GET  + /vehicle            + ?*) { [ 'asset', 'vehicle',        @_ ] },
   sub (GET  + /vehicle/*          + ?*) { [ 'asset', 'vehicle',        @_ ] },
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Controller::Main - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Controller::Main;
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